import Foundation
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
    var lastStartedGeneration: UUID?
    var startDelayNanoseconds: UInt64 = 0
    var errorOnStart: Error?

    var events: AsyncStream<PresenceMonitorEvent> {
        broadcaster.makeStream()
    }

    func start(calibration: Calibration, generation: UUID) async throws {
        startCount += 1
        lastStartedGeneration = generation
        if startDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: startDelayNanoseconds)
        }
        if let errorOnStart = errorOnStart {
            throw errorOnStart
        }
    }

    func stop() async {
        stopCount += 1
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
