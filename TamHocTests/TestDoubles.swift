import Foundation
import UIKit
import StudyCore
@testable import TamHoc

final class FakeClock: SessionClock, @unchecked Sendable {
    private let lock = NSLock()
    private var currentMonotonic: Double
    private var currentWall: Date

    init(
        monotonicSeconds: Double = 0,
        wallDate: Date = Date(timeIntervalSince1970: 1_795_400_000)
    ) {
        self.currentMonotonic = monotonicSeconds
        self.currentWall = wallDate
    }

    func now() -> TimePoint {
        lock.lock()
        defer { lock.unlock() }
        return TimePoint(monotonicSeconds: currentMonotonic, wallDate: currentWall)
    }

    func advance(by seconds: Double, wallOffset: Double? = nil) {
        lock.lock()
        defer { lock.unlock() }
        currentMonotonic += seconds
        currentWall = currentWall.addingTimeInterval(wallOffset ?? seconds)
    }

    func set(monotonicSeconds: Double, wallDate: Date? = nil) {
        lock.lock()
        defer { lock.unlock() }
        currentMonotonic = monotonicSeconds
        if let wallDate = wallDate {
            currentWall = wallDate
        }
    }
}

@MainActor
final class FakeGuidedAccessMonitor: GuidedAccessMonitoring {
    var isEnabled: Bool
    private let broadcaster = StreamBroadcaster<Bool>()

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    var changes: AsyncStream<Bool> {
        broadcaster.makeStream()
    }

    func send(_ enabled: Bool) {
        isEnabled = enabled
        broadcaster.yield(enabled)
    }
}

@MainActor
final class FakePresenceMonitor: PresenceMonitoring {
    private let broadcaster = StreamBroadcaster<PresenceMonitorEvent>()
    var startCount = 0
    var stopCount = 0
    var isCapturing = false
    var lastStartedGeneration: UUID?
    var startedGenerations: [UUID] = []
    var startDelayNanoseconds: UInt64 = 0
    var errorOnStart: Error?

    private var shouldSuspendNextStart = false
    private var suspendedContinuation: CheckedContinuation<Void, Never>?
    private var suspendedEnteredContinuation: CheckedContinuation<Void, Never>?

    var events: AsyncStream<PresenceMonitorEvent> {
        broadcaster.makeStream()
    }

    func suspendNextStart() {
        shouldSuspendNextStart = true
    }

    func waitUntilStartSuspended() async {
        if suspendedContinuation != nil { return }
        await withCheckedContinuation { continuation in
            suspendedEnteredContinuation = continuation
        }
    }

    func resumeSuspendedStart() {
        suspendedContinuation?.resume()
        suspendedContinuation = nil
    }

    func start(calibration: Calibration, generation: UUID) async throws {
        startCount += 1
        lastStartedGeneration = generation
        startedGenerations.append(generation)

        if shouldSuspendNextStart {
            shouldSuspendNextStart = false
            await withCheckedContinuation { continuation in
                suspendedContinuation = continuation
                suspendedEnteredContinuation?.resume()
                suspendedEnteredContinuation = nil
            }
        }

        if startDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: startDelayNanoseconds)
        }
        if let errorOnStart = errorOnStart {
            throw errorOnStart
        }
        isCapturing = true
    }

    func stop() async {
        stopCount += 1
        isCapturing = false
    }

    func emit(_ sample: PresenceSample, generation: UUID) {
        broadcaster.yield(PresenceMonitorEvent(generation: generation, sample: sample))
    }
}

final class FakeCameraAuthorizer: CameraAuthorizing, @unchecked Sendable {
    var status: CameraAuthorizationState
    var grantAccessResult: Bool
    var frontCameraAvailable: Bool
    private(set) var requestAccessCallCount = 0

    init(
        status: CameraAuthorizationState = .authorized,
        grantAccessResult: Bool = true,
        frontCameraAvailable: Bool = true
    ) {
        self.status = status
        self.grantAccessResult = grantAccessResult
        self.frontCameraAvailable = frontCameraAvailable
    }

    func authorizationStatus() -> CameraAuthorizationState { status }

    func requestAccess() async -> Bool {
        requestAccessCallCount += 1
        return grantAccessResult
    }

    func hasFrontCamera() -> Bool { frontCameraAvailable }
}

@MainActor
final class SpyWarningPlayer: WarningPlaying {
    var playCount = 0

    func playWarning() {
        playCount += 1
    }
}

@MainActor
final class FakeIdleTimerController: IdleTimerControlling {
    private(set) var isAwakeDisabled = false
    private(set) var beginCount = 0
    private(set) var restoreCount = 0

    func beginKeepingAwake() {
        beginCount += 1
        isAwakeDisabled = true
    }

    func restore() {
        restoreCount += 1
        isAwakeDisabled = false
    }
}

@MainActor
final class FakeBackgroundTaskManager: BackgroundTaskManaging {
    func beginBackgroundTask(name: String, expirationHandler: @escaping @Sendable () -> Void) -> UIBackgroundTaskIdentifier {
        UIBackgroundTaskIdentifier(rawValue: 1)
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {}
}

actor MockSessionRepository: SessionRepository {
    var stored: [UUID: SessionRecord] = [:]
    var savedSequence: [SessionRecord] = []
    var saveDelayNanoseconds: UInt64 = 0
    var failNextNonInitialSave = false
    var errorOnSave: Error?
    var errorOnLoad: Error?

    func seed(_ record: SessionRecord) {
        stored[record.id] = record
    }

    func setSaveDelay(_ nanos: UInt64) {
        saveDelayNanoseconds = nanos
    }

    func setErrorOnSave(_ error: Error?) {
        errorOnSave = error
    }

    func loadAll() async throws -> RepositoryReadResult {
        if let errorOnLoad = errorOnLoad {
            throw errorOnLoad
        }
        return RepositoryReadResult(records: Array(stored.values), quarantinedIDs: [])
    }

    func save(_ record: SessionRecord) async throws {
        if saveDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: saveDelayNanoseconds)
        }
        if let errorOnSave = errorOnSave {
            throw errorOnSave
        }
        stored[record.id] = record
        savedSequence.append(record)
    }

    func delete(id: UUID) async throws {
        stored.removeValue(forKey: id)
    }
}
