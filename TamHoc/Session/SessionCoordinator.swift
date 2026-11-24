import Foundation
import UIKit
import StudyCore

public enum CoordinatorError: Error, Equatable {
    case alreadyRunning
    case previousSessionFinalizing
    case guidedAccessRequired
    case calibrationRequired
    case startCancelled
    case invalidClock
    case thermalCritical
}

@MainActor
public protocol IdleTimerControlling: AnyObject {
    func beginKeepingAwake()
    func restore()
}

@MainActor
public final class UIApplicationIdleTimerController: IdleTimerControlling {
    private var savedPreviousValue: Bool?

    public init() {}

    public func beginKeepingAwake() {
        if savedPreviousValue == nil {
            savedPreviousValue = UIApplication.shared.isIdleTimerDisabled
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    public func restore() {
        if let previous = savedPreviousValue {
            UIApplication.shared.isIdleTimerDisabled = previous
            savedPreviousValue = nil
        }
    }
}

@MainActor
public protocol BackgroundTaskManaging: AnyObject {
    func beginBackgroundTask(name: String, expirationHandler: @escaping @Sendable () -> Void) -> UIBackgroundTaskIdentifier
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier)
}

@MainActor
public final class UIApplicationBackgroundTaskManager: BackgroundTaskManaging {
    public init() {}

    public func beginBackgroundTask(
        name: String,
        expirationHandler: @escaping @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: expirationHandler)
    }

    public func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(identifier)
    }
}

@MainActor
public final class SessionCoordinator: ObservableObject {
    @Published public private(set) var snapshot: SessionSnapshot?
    @Published public private(set) var activeConfiguration: SessionConfiguration?
    @Published public private(set) var lastCompletedRecord: SessionRecord?
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var persistenceWarningMessage: String?
    @Published public private(set) var recoveredInterruptedRecords: [SessionRecord] = []
    @Published public private(set) var quarantinedCount: Int = 0
    @Published public private(set) var unsupportedSchemaFiles: [String] = []
    @Published public private(set) var isStarting: Bool = false
    @Published public private(set) var isFinalizing: Bool = false

    private let clock: SessionClock
    private let lockMonitor: GuidedAccessMonitoring
    private let presenceMonitor: PresenceMonitoring
    private let repository: SessionRepository
    private let warningPlayer: WarningPlaying
    private let idleTimerController: IdleTimerControlling
    private let backgroundTaskManager: BackgroundTaskManaging
    private let thermalStateProvider: @Sendable () -> ProcessInfo.ThermalState

    private var engine: SessionEngine?
    private var activeGeneration: UUID?
    private var activeCaptureToken: UUID?
    private var sessionCaptureTokens: Set<UUID> = []
    private var preStartThermalToken: UUID?
    private var pendingGeneration: UUID?
    private var activeCalibration: Calibration?
    private var currentActivity: ActivityState

    private var tickTask: Task<Void, Never>?
    private var lockTask: Task<Void, Never>?
    private var presenceTask: Task<Void, Never>?
    private var resumeCameraTask: Task<Void, Never>?
    private var stopCameraTask: Task<Void, Never>?
    private var finalizeTask: Task<Void, Never>?
    private var thermalObserver: NotificationObserverBox?
    private var highestPresenceSequence: UInt64 = 0

    // Serialized persistence queue so stale checkpoints never overwrite completion
    private var activeSaveTask: Task<Void, Error>?
    private var pendingSaveRecord: SessionRecord?

    public init(
        clock: SessionClock,
        lockMonitor: GuidedAccessMonitoring,
        presenceMonitor: PresenceMonitoring,
        repository: SessionRepository,
        warningPlayer: WarningPlaying,
        idleTimerController: IdleTimerControlling? = nil,
        backgroundTaskManager: BackgroundTaskManaging? = nil,
        initialActivity: ActivityState = .active,
        thermalStateProvider: @escaping @Sendable () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState }
    ) {
        self.clock = clock
        self.lockMonitor = lockMonitor
        self.presenceMonitor = presenceMonitor
        self.repository = repository
        self.warningPlayer = warningPlayer
        self.idleTimerController = idleTimerController ?? UIApplicationIdleTimerController()
        self.backgroundTaskManager = backgroundTaskManager ?? UIApplicationBackgroundTaskManager()
        self.currentActivity = initialActivity
        self.thermalStateProvider = thermalStateProvider
    }

    public func recoverUnfinishedSessions() async throws {
        let result = try await repository.loadAll()
        self.quarantinedCount = result.quarantinedIDs.count
        self.unsupportedSchemaFiles = result.unsupportedSchemaFiles

        var recovered: [SessionRecord] = []
        for record in result.records where record.status == .running {
            let interrupted = SessionRecovery.interruptUnfinished(record)
            try await repository.save(interrupted)
            recovered.append(interrupted)
        }
        self.recoveredInterruptedRecords = recovered
    }

    public func start(configuration: SessionConfiguration, calibration: Calibration?) async throws {
        guard !isFinalizing, finalizeTask == nil else {
            throw CoordinatorError.previousSessionFinalizing
        }
        guard engine == nil, pendingGeneration == nil else {
            throw CoordinatorError.alreadyRunning
        }
        guard currentActivity == .active else {
            throw CoordinatorError.startCancelled
        }
        guard lockMonitor.isEnabled else {
            throw CoordinatorError.guidedAccessRequired
        }
        if configuration.presenceMode == .cameraVerified {
            guard calibration != nil else {
                throw CoordinatorError.calibrationRequired
            }
            guard thermalStateProvider() != .critical else {
                throw CoordinatorError.thermalCritical
            }
        }

        let generation = UUID()
        let initialCaptureToken = UUID()
        pendingGeneration = generation
        activeCaptureToken = (configuration.presenceMode == .cameraVerified) ? initialCaptureToken : nil
        isStarting = true
        lastErrorMessage = nil
        persistenceWarningMessage = nil

        if configuration.presenceMode == .cameraVerified, let calibration = calibration {
            let preStartEvents = presenceMonitor.events
            preStartThermalToken = nil
            let preStartTask = Task { [weak self] in
                for await event in preStartEvents {
                    if event.generation == initialCaptureToken,
                       case .unknown(.thermal) = event.sample.value {
                        self?.preStartThermalToken = initialCaptureToken
                        break
                    }
                }
            }

            do {
                try await presenceMonitor.start(calibration: calibration, generation: initialCaptureToken)
            } catch {
                preStartTask.cancel()
                await preStartTask.value
                preStartThermalToken = nil
                if pendingGeneration == generation {
                    pendingGeneration = nil
                    activeCaptureToken = nil
                    isStarting = false
                }
                await presenceMonitor.stop(generation: initialCaptureToken)
                throw error
            }

            // Process buffered startup events before checking the thermal result.
            preStartTask.cancel()
            await preStartTask.value
            let sawThermalDuringStart = (preStartThermalToken == initialCaptureToken)
            preStartThermalToken = nil

            if sawThermalDuringStart || thermalStateProvider() == .critical {
                activeCaptureToken = nil
                await presenceMonitor.stop(generation: initialCaptureToken)
                if pendingGeneration == generation {
                    pendingGeneration = nil
                }
                isStarting = false
                throw CoordinatorError.thermalCritical
            }

            if pendingGeneration != generation || Task.isCancelled || currentActivity != .active {
                activeCaptureToken = nil
                await presenceMonitor.stop(generation: initialCaptureToken)
                if pendingGeneration == generation {
                    pendingGeneration = nil
                }
                isStarting = false
                throw CoordinatorError.startCancelled
            }

            guard lockMonitor.isEnabled else {
                activeCaptureToken = nil
                await presenceMonitor.stop(generation: initialCaptureToken)
                pendingGeneration = nil
                isStarting = false
                throw CoordinatorError.guidedAccessRequired
            }
        }

        let startTime = clock.now()
        guard startTime.monotonicSeconds.isFinite else {
            activeCaptureToken = nil
            if configuration.presenceMode == .cameraVerified {
                await presenceMonitor.stop(generation: initialCaptureToken)
            }
            pendingGeneration = nil
            isStarting = false
            throw CoordinatorError.invalidClock
        }

        var initialEngine = SessionEngine(
            id: UUID(),
            configuration: configuration,
            startedAt: startTime
        )

        do {
            try await saveSerialized(initialEngine.record)
        } catch {
            activeCaptureToken = nil
            if configuration.presenceMode == .cameraVerified {
                await presenceMonitor.stop(generation: initialCaptureToken)
            }
            pendingGeneration = nil
            isStarting = false
            throw error
        }

        if pendingGeneration != generation || Task.isCancelled || currentActivity != .active {
            if let _ = try? initialEngine.handle(.finish(.userEnded), at: clock.now()) {
                try? await saveSerialized(initialEngine.record)
            }
            activeCaptureToken = nil
            if configuration.presenceMode == .cameraVerified {
                await presenceMonitor.stop(generation: initialCaptureToken)
            }
            if pendingGeneration == generation {
                pendingGeneration = nil
            }
            isStarting = false
            throw CoordinatorError.startCancelled
        }

        guard lockMonitor.isEnabled else {
            if let _ = try? initialEngine.handle(.finish(.lockReleased), at: clock.now()) {
                try? await saveSerialized(initialEngine.record)
            }
            activeCaptureToken = nil
            if configuration.presenceMode == .cameraVerified {
                await presenceMonitor.stop(generation: initialCaptureToken)
            }
            pendingGeneration = nil
            isStarting = false
            throw CoordinatorError.guidedAccessRequired
        }

        if configuration.presenceMode == .cameraVerified && thermalStateProvider() == .critical {
            if let _ = try? initialEngine.handle(.finish(.thermalLimit), at: clock.now()) {
                try? await saveSerialized(initialEngine.record)
            }
            activeCaptureToken = nil
            await presenceMonitor.stop(generation: initialCaptureToken)
            pendingGeneration = nil
            isStarting = false
            throw CoordinatorError.thermalCritical
        }

        self.pendingGeneration = nil
        self.isStarting = false
        self.activeGeneration = generation
        self.activeConfiguration = configuration
        self.activeCalibration = calibration
        self.sessionCaptureTokens = (configuration.presenceMode == .cameraVerified) ? [initialCaptureToken] : []
        self.highestPresenceSequence = 0
        self.resumeCameraTask = nil
        self.finalizeTask = nil
        self.engine = initialEngine
        self.snapshot = initialEngine.snapshot

        idleTimerController.beginKeepingAwake()
        startConsumers(for: generation, mode: configuration.presenceMode)
    }

    public func receiveActivity(_ state: ActivityState) {
        guard state != currentActivity else { return }
        currentActivity = state

        guard let gen = activeGeneration, engine != nil else {
            if state != .active {
                idleTimerController.restore()
                if pendingGeneration != nil {
                    let tokenToStop = activeCaptureToken
                    pendingGeneration = nil
                    activeCaptureToken = nil
                    isStarting = false
                    if let tokenToStop = tokenToStop {
                        let monitor = presenceMonitor
                        Task {
                            await monitor.stop(generation: tokenToStop)
                        }
                    }
                }
            }
            return
        }

        if state != .active {
            let tokenToStop = activeCaptureToken
            resumeCameraTask?.cancel()
            resumeCameraTask = nil
            activeCaptureToken = nil
            tickTask?.cancel()
            tickTask = nil
            idleTimerController.restore()
            handleEngineInput(.activityChanged(state))
            let bgID = backgroundTaskManager.beginBackgroundTask(name: "TamHocCheckpoint") {}
            let priorStop = stopCameraTask
            let monitor = presenceMonitor
            stopCameraTask = Task { [weak self] in
                await priorStop?.value
                if let tokenToStop = tokenToStop {
                    await monitor.stop(generation: tokenToStop)
                }
                if let self = self {
                    await self.flushPendingSave()
                    self.backgroundTaskManager.endBackgroundTask(bgID)
                } else {
                    await MainActor.run {
                        UIApplication.shared.endBackgroundTask(bgID)
                    }
                }
            }
        } else {
            // Tick up to current clock BEFORE deciding whether to restart camera
            handleEngineInput(.activityChanged(.active))

            guard activeGeneration == gen,
                  let currentEngine = engine,
                  !currentEngine.record.status.isTerminal else {
                return
            }

            if !lockMonitor.isEnabled {
                handleEngineInput(.lockChanged(false))
                return
            }

            idleTimerController.beginKeepingAwake()
            startTickLoop(for: gen)

            if currentEngine.record.configuration.presenceMode == .cameraVerified,
               let calibration = activeCalibration {
                resumeCameraTask?.cancel()
                let resumeToken = UUID()
                activeCaptureToken = resumeToken
                sessionCaptureTokens.insert(resumeToken)
                let priorStop = stopCameraTask
                let monitor = presenceMonitor
                let clockRef = clock
                resumeCameraTask = Task { [weak self] in
                    await priorStop?.value
                    let canStart: Bool = {
                        guard !Task.isCancelled,
                              let s = self,
                              s.activeGeneration == gen,
                              s.activeCaptureToken == resumeToken,
                              s.currentActivity == .active,
                              !s.isFinalizing else {
                            return false
                        }
                        return true
                    }()
                    guard canStart else { return }

                    do {
                        try await monitor.start(calibration: calibration, generation: resumeToken)
                        let keepRunning: Bool = {
                            guard !Task.isCancelled,
                                  let s = self,
                                  s.activeGeneration == gen,
                                  s.activeCaptureToken == resumeToken,
                                  s.currentActivity == .active,
                                  !s.isFinalizing else {
                                return false
                            }
                            return true
                        }()
                        if !keepRunning {
                            await monitor.stop(generation: resumeToken)
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled,
                              let s = self,
                              s.activeGeneration == gen,
                              s.activeCaptureToken == resumeToken,
                              s.currentActivity == .active,
                              !s.isFinalizing else {
                            return
                        }
                        s.highestPresenceSequence &+= 1
                        s.handleEngineInput(.sample(PresenceSample(
                            sequence: s.highestPresenceSequence,
                            capturedMonotonicSeconds: clockRef.now().monotonicSeconds,
                            value: .unknown(.cameraUnavailable)
                        )))
                    }
                }
            }
        }
    }

    public func endEarly() async {
        if pendingGeneration != nil {
            let tokenToStop = activeCaptureToken
            pendingGeneration = nil
            activeCaptureToken = nil
            isStarting = false
            if let tokenToStop = tokenToStop {
                await presenceMonitor.stop(generation: tokenToStop)
            }
            return
        }

        let pendingResume = resumeCameraTask
        pendingResume?.cancel()

        if let _ = engine, activeGeneration != nil {
            handleEngineInput(.finish(.userEnded))
        }
        await pendingResume?.value
        await finalizeTask?.value
        await flushPendingSave()
    }

    public func waitForFinalization() async {
        await finalizeTask?.value
        await stopCameraTask?.value
        await flushPendingSave()
    }

    public func clearCompletedSummary() {
        lastCompletedRecord = nil
        snapshot = nil
        activeConfiguration = nil
        persistenceWarningMessage = nil
        lastErrorMessage = nil
    }

    private func startConsumers(for generation: UUID, mode: PresenceMode) {
        startTickLoop(for: generation)

        let lockChanges = lockMonitor.changes
        lockTask = Task { [weak self] in
            for await isLocked in lockChanges {
                guard !Task.isCancelled else { break }
                guard let self = self, self.activeGeneration == generation else { break }
                if !isLocked {
                    self.handleEngineInput(.lockChanged(false))
                    break
                }
            }
        }

        if mode == .cameraVerified {
            let events = presenceMonitor.events
            presenceTask = Task { [weak self] in
                for await event in events {
                    guard !Task.isCancelled else { break }
                    guard let self = self,
                          self.activeGeneration == generation,
                          let expectedToken = self.activeCaptureToken,
                          event.generation == expectedToken else { continue }

                    if case .unknown(.thermal) = event.sample.value {
                        self.handleEngineInput(.finish(.thermalLimit))
                        break
                    }
                    if event.sample.sequence > self.highestPresenceSequence {
                        self.highestPresenceSequence = event.sample.sequence
                    }
                    self.handleEngineInput(.sample(event.sample))
                }
            }
        }

        thermalObserver = NotificationObserverBox(
            center: .default,
            registrations: [
                (ProcessInfo.thermalStateDidChangeNotification, { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self,
                              self.activeGeneration == generation else { return }
                        if ProcessInfo.processInfo.thermalState == .critical {
                            self.handleEngineInput(.finish(.thermalLimit))
                        }
                    }
                })
            ]
        )
    }

    private func startTickLoop(for generation: UUID) {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self = self, self.activeGeneration == generation else { break }
                guard self.currentActivity == .active else { continue }
                self.handleEngineInput(.tick)
            }
        }
    }

    private func handleEngineInput(_ input: SessionInput) {
        guard let generation = activeGeneration, var currentEngine = engine else { return }
        let now = clock.now()

        let update: SessionUpdate
        do {
            update = try currentEngine.handle(input, at: now)
        } catch EngineError.nonMonotonicTime {
            lastErrorMessage = "Đồng hồ hệ thống gặp lỗi không liên tục; phiên đã dừng."
            var failedRecord = currentEngine.record
            failedRecord.status = .endedEarly(.clockFailure)
            failedRecord.events.append(
                SessionEvent(
                    elapsedSeconds: currentEngine.record.elapsedSeconds,
                    kind: .sessionEnded,
                    detail: .clockFailure
                )
            )
            failedRecord.revision += 1

            self.snapshot = SessionSnapshot(
                status: failedRecord.status,
                remainingSeconds: max(0, failedRecord.configuration.plannedSeconds - failedRecord.elapsedSeconds),
                elapsedSeconds: failedRecord.elapsedSeconds,
                secondsByBucket: failedRecord.secondsByBucket,
                presence: .unknown(.cameraUnavailable)
            )
            finalizeSession(generation: generation, finalRecord: failedRecord, reason: .clockFailure)
            return
        } catch EngineError.invalidSample {
            return
        } catch {
            return
        }

        self.engine = currentEngine
        self.snapshot = update.snapshot

        for effect in update.effects {
            switch effect {
            case .warnAbsence:
                warningPlayer.playWarning()
            case .longAbsence:
                break
            case .checkpoint:
                enqueueCheckpointSave(currentEngine.record)
            case .finish(let reason):
                let finalRecord = currentEngine.record
                finalizeSession(generation: generation, finalRecord: finalRecord, reason: reason)
            }
        }
    }

    private func finalizeSession(generation: UUID, finalRecord: SessionRecord, reason: EndReason) {
        guard activeGeneration == generation, !isFinalizing else { return }
        isFinalizing = true
        activeGeneration = nil

        tickTask?.cancel()
        tickTask = nil
        lockTask?.cancel()
        lockTask = nil
        presenceTask?.cancel()
        presenceTask = nil
        let pendingStop = stopCameraTask
        let pendingResume = resumeCameraTask
        let ownedTokens = sessionCaptureTokens
        stopCameraTask = nil
        resumeCameraTask?.cancel()
        resumeCameraTask = nil
        activeCaptureToken = nil
        sessionCaptureTokens.removeAll()
        thermalObserver?.invalidate()
        thermalObserver = nil

        idleTimerController.restore()
        lastCompletedRecord = finalRecord
        engine = nil

        if reason == .storageFailure {
            persistenceWarningMessage = "Không thể lưu tiến độ phiên học. Phiên đã dừng sớm."
        }

        let monitor = presenceMonitor
        finalizeTask = Task { [weak self] in
            defer {
                self?.finalizeTask = nil
                self?.isFinalizing = false
            }
            await pendingStop?.value
            await pendingResume?.value
            for token in ownedTokens {
                await monitor.stop(generation: token)
            }
            guard let self = self else { return }
            do {
                try await self.saveSerialized(finalRecord)
            } catch {
                if reason == .clockFailure {
                    self.persistenceWarningMessage = "Phiên học dừng do lỗi đồng hồ và không thể lưu kết quả."
                } else {
                    self.persistenceWarningMessage = "Phiên học đã kết thúc nhưng không thể lưu kết quả lên máy."
                }
            }
        }
    }

    private func enqueueCheckpointSave(_ record: SessionRecord) {
        if let pending = pendingSaveRecord, pending.revision > record.revision {
            return
        }
        pendingSaveRecord = record
        guard activeSaveTask == nil else { return }
        startDrainSaveLoop()
    }

    private func saveSerialized(_ record: SessionRecord) async throws {
        if let existing = activeSaveTask {
            try? await existing.value
        }
        if let pending = pendingSaveRecord, pending.revision > record.revision {
            return
        }
        pendingSaveRecord = record
        if activeSaveTask == nil {
            startDrainSaveLoop()
        }
        if let drain = activeSaveTask {
            try await drain.value
        }
    }

    private func startDrainSaveLoop() {
        let task = Task { [weak self] in
            guard let self = self else { return }
            defer { self.activeSaveTask = nil }
            while let next = self.pendingSaveRecord {
                self.pendingSaveRecord = nil
                do {
                    try await self.repository.save(next)
                } catch {
                    if self.activeGeneration != nil && !self.isFinalizing {
                        self.handleEngineInput(.finish(.storageFailure))
                    } else {
                        self.persistenceWarningMessage = "Phiên học đã kết thúc nhưng không thể lưu kết quả lên máy."
                    }
                    throw error
                }
            }
        }
        activeSaveTask = task
    }

    private func flushPendingSave() async {
        if let existing = activeSaveTask {
            try? await existing.value
        }
    }
}
