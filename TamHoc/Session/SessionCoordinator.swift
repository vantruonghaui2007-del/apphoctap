import Foundation
import UIKit
import StudyCore

public enum CoordinatorError: Error, Equatable {
    case alreadyRunning
    case guidedAccessRequired
    case calibrationRequired
    case startCancelled
    case invalidClock
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

    private let clock: SessionClock
    private let lockMonitor: GuidedAccessMonitoring
    private let presenceMonitor: PresenceMonitoring
    private let repository: SessionRepository
    private let warningPlayer: WarningPlaying
    private let idleTimerController: IdleTimerControlling
    private let backgroundTaskManager: BackgroundTaskManaging

    private var engine: SessionEngine?
    private var activeGeneration: UUID?
    private var activeCaptureToken: UUID?
    private var pendingGeneration: UUID?
    private var activeCalibration: Calibration?
    private var currentActivity: ActivityState
    private var isFinalizing = false

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
        initialActivity: ActivityState = .active
    ) {
        self.clock = clock
        self.lockMonitor = lockMonitor
        self.presenceMonitor = presenceMonitor
        self.repository = repository
        self.warningPlayer = warningPlayer
        self.idleTimerController = idleTimerController ?? UIApplicationIdleTimerController()
        self.backgroundTaskManager = backgroundTaskManager ?? UIApplicationBackgroundTaskManager()
        self.currentActivity = initialActivity
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
        }

        let generation = UUID()
        let initialCaptureToken = UUID()
        pendingGeneration = generation
        activeCaptureToken = (configuration.presenceMode == .cameraVerified) ? initialCaptureToken : nil
        isStarting = true
        lastErrorMessage = nil
        persistenceWarningMessage = nil

        if configuration.presenceMode == .cameraVerified, let calibration = calibration {
            do {
                try await presenceMonitor.start(calibration: calibration, generation: initialCaptureToken)
            } catch {
                if pendingGeneration == generation {
                    pendingGeneration = nil
                    activeCaptureToken = nil
                    isStarting = false
                }
                await presenceMonitor.stop()
                throw error
            }

            if pendingGeneration != generation || Task.isCancelled || currentActivity != .active {
                activeCaptureToken = nil
                await presenceMonitor.stop()
                if pendingGeneration == generation {
                    pendingGeneration = nil
                }
                isStarting = false
                throw CoordinatorError.startCancelled
            }

            guard lockMonitor.isEnabled else {
                activeCaptureToken = nil
                await presenceMonitor.stop()
                pendingGeneration = nil
                isStarting = false
                throw CoordinatorError.guidedAccessRequired
            }
        }

        let startTime = clock.now()
        guard startTime.monotonicSeconds.isFinite else {
            activeCaptureToken = nil
            await presenceMonitor.stop()
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
            await presenceMonitor.stop()
            pendingGeneration = nil
            isStarting = false
            throw error
        }

        if pendingGeneration != generation || Task.isCancelled || currentActivity != .active {
            if let _ = try? initialEngine.handle(.finish(.userEnded), at: clock.now()) {
                try? await saveSerialized(initialEngine.record)
            }
            activeCaptureToken = nil
            await presenceMonitor.stop()
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
            await presenceMonitor.stop()
            pendingGeneration = nil
            isStarting = false
            throw CoordinatorError.guidedAccessRequired
        }

        self.pendingGeneration = nil
        self.isStarting = false
        self.activeGeneration = generation
        self.activeConfiguration = configuration
        self.activeCalibration = calibration
        self.isFinalizing = false
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
                    pendingGeneration = nil
                    activeCaptureToken = nil
                    isStarting = false
                    Task { [weak self] in
                        await self?.presenceMonitor.stop()
                    }
                }
            }
            return
        }

        if state != .active {
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
                await monitor.stop()
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
                            await monitor.stop()
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
            pendingGeneration = nil
            activeCaptureToken = nil
            isStarting = false
            await presenceMonitor.stop()
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

    public func clearCompletedSummary() {
        lastCompletedRecord = nil
        snapshot = nil
        activeConfiguration = nil
        persistenceWarningMessage = nil
        lastErrorMessage = nil
    }

    private func startConsumers(for generation: UUID, mode: PresenceMode) {
        startTickLoop(for: generation)

        lockTask = Task { [weak self] in
            guard let self = self else { return }
            for await isLocked in self.lockMonitor.changes {
                guard !Task.isCancelled, self.activeGeneration == generation else { break }
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
            Task { [weak self] in
                await self?.finalizeOnClockFailure(generation: generation, record: currentEngine.record)
            }
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
        stopCameraTask = nil
        resumeCameraTask?.cancel()
        resumeCameraTask = nil
        activeCaptureToken = nil
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
            await pendingStop?.value
            await pendingResume?.value
            await monitor.stop()
            guard let self = self else { return }
            do {
                try await self.saveSerialized(finalRecord)
            } catch {
                self.persistenceWarningMessage = "Phiên học đã kết thúc nhưng không thể lưu kết quả lên máy."
            }
        }
    }

    private func finalizeOnClockFailure(generation: UUID, record: SessionRecord) async {
        guard activeGeneration == generation, !isFinalizing else { return }
        isFinalizing = true
        activeGeneration = nil

        tickTask?.cancel()
        tickTask = nil
        lockTask?.cancel()
        lockTask = nil
        presenceTask?.cancel()
        presenceTask = nil
        resumeCameraTask?.cancel()
        resumeCameraTask = nil
        activeCaptureToken = nil
        thermalObserver?.invalidate()
        thermalObserver = nil

        idleTimerController.restore()

        var failedRecord = record
        failedRecord.status = .endedEarly(.clockFailure)
        failedRecord.events.append(
            SessionEvent(elapsedSeconds: record.elapsedSeconds, kind: .sessionEnded, detail: .clockFailure)
        )
        failedRecord.revision += 1

        lastCompletedRecord = failedRecord
        snapshot = SessionSnapshot(
            status: failedRecord.status,
            remainingSeconds: max(0, failedRecord.configuration.plannedSeconds - failedRecord.elapsedSeconds),
            elapsedSeconds: failedRecord.elapsedSeconds,
            secondsByBucket: failedRecord.secondsByBucket,
            presence: .unknown(.cameraUnavailable)
        )
        engine = nil

        await presenceMonitor.stop()
        do {
            try await saveSerialized(failedRecord)
        } catch {
            persistenceWarningMessage = "Phiên học dừng do lỗi đồng hồ và không thể lưu kết quả."
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
