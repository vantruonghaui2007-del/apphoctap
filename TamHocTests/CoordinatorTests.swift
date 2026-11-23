import XCTest
import StudyCore
@testable import TamHoc

@MainActor
final class CoordinatorTests: XCTestCase {
    private func makeCoordinator(
        clock: FakeClock = FakeClock(),
        lock: FakeGuidedAccessMonitor = FakeGuidedAccessMonitor(isEnabled: true),
        presence: FakePresenceMonitor = FakePresenceMonitor(),
        repo: MockSessionRepository = MockSessionRepository(),
        warning: SpyWarningPlayer = SpyWarningPlayer(),
        idle: FakeIdleTimerController = FakeIdleTimerController()
    ) -> SessionCoordinator {
        SessionCoordinator(
            clock: clock,
            lockMonitor: lock,
            presenceMonitor: presence,
            repository: repo,
            warningPlayer: warning,
            idleTimerController: idle,
            backgroundTaskManager: FakeBackgroundTaskManager()
        )
    }

    private func timerConfig(seconds: Double = 120) throws -> SessionConfiguration {
        try SessionConfiguration.validated(plannedSeconds: seconds, presenceMode: .timerOnly, warningsEnabled: true)
    }

    private func cameraConfig(seconds: Double = 120) throws -> SessionConfiguration {
        try SessionConfiguration.validated(plannedSeconds: seconds, presenceMode: .cameraVerified, warningsEnabled: true)
    }

    func testStartRequiresRealLock() async throws {
        let lock = FakeGuidedAccessMonitor(isEnabled: false)
        let presence = FakePresenceMonitor()
        let coordinator = makeCoordinator(lock: lock, presence: presence)

        do {
            try await coordinator.start(configuration: try cameraConfig(), calibration: .defaultCentered)
            XCTFail("Expected guidedAccessRequired")
        } catch let err as CoordinatorError {
            XCTAssertEqual(err, .guidedAccessRequired)
        }

        XCTAssertNil(coordinator.snapshot)
        XCTAssertEqual(presence.startCount, 0)
    }

    func testCameraModeRequiresValidCalibration() async throws {
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let presence = FakePresenceMonitor()
        let coordinator = makeCoordinator(lock: lock, presence: presence)

        do {
            try await coordinator.start(configuration: try cameraConfig(), calibration: nil)
            XCTFail("Expected calibrationRequired")
        } catch let err as CoordinatorError {
            XCTAssertEqual(err, .calibrationRequired)
        }

        XCTAssertNil(coordinator.snapshot)
        XCTAssertEqual(presence.startCount, 0)
    }

    func testInitialSaveFailurePreventsRunning() async throws {
        enum FakeIOError: Error { case diskFull }
        let repo = MockSessionRepository()
        await repo.setErrorOnSave(FakeIOError.diskFull)
        let presence = FakePresenceMonitor()
        let coordinator = makeCoordinator(presence: presence, repo: repo)

        do {
            try await coordinator.start(configuration: try cameraConfig(), calibration: .defaultCentered)
            XCTFail("Expected initial save failure to block starting")
        } catch {
            // Expected error
        }

        XCTAssertNil(coordinator.snapshot)
        XCTAssertGreaterThanOrEqual(presence.stopCount, 1)
    }

    func testLockLossEndsOnlyOnce() async throws {
        let clock = FakeClock(monotonicSeconds: 0)
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let presence = FakePresenceMonitor()
        let repo = MockSessionRepository()
        let idle = FakeIdleTimerController()
        let coordinator = makeCoordinator(clock: clock, lock: lock, presence: presence, repo: repo, idle: idle)

        try await coordinator.start(configuration: try cameraConfig(), calibration: .defaultCentered)
        XCTAssertEqual(coordinator.snapshot?.status, .running)
        XCTAssertTrue(idle.isAwakeDisabled)

        try? await Task.sleep(nanoseconds: 20_000_000)
        clock.advance(by: 15)

        // Emit lock loss twice
        lock.send(false)
        lock.send(false)
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Calling endEarly after lock loss must remain idempotent
        await coordinator.endEarly()

        XCTAssertEqual(coordinator.lastCompletedRecord?.status, .endedEarly(.lockReleased))
        XCTAssertEqual(coordinator.lastCompletedRecord?.events.filter { $0.kind == .lockReleased }.count, 1)
        XCTAssertFalse(idle.isAwakeDisabled)
        XCTAssertGreaterThanOrEqual(presence.stopCount, 1)
    }

    func testInactiveStopsPresenceButDeadlineAdvances() async throws {
        let clock = FakeClock(monotonicSeconds: 0)
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let presence = FakePresenceMonitor()
        let repo = MockSessionRepository()
        let idle = FakeIdleTimerController()
        let coordinator = makeCoordinator(clock: clock, lock: lock, presence: presence, repo: repo, idle: idle)

        try await coordinator.start(configuration: try cameraConfig(seconds: 120), calibration: .defaultCentered)
        XCTAssertEqual(presence.startCount, 1)

        clock.advance(by: 10)
        coordinator.receiveActivity(.inactive)
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertGreaterThanOrEqual(presence.stopCount, 1)
        XCTAssertFalse(idle.isAwakeDisabled)

        // Advance past deadline while inactive
        clock.advance(by: 115)
        coordinator.receiveActivity(.active)
        try? await Task.sleep(nanoseconds: 40_000_000)

        // Must complete without restarting camera
        XCTAssertEqual(presence.startCount, 1)
        XCTAssertEqual(coordinator.lastCompletedRecord?.status, .completed)
        XCTAssertEqual(coordinator.lastCompletedRecord?.elapsedSeconds ?? -1, 120, accuracy: 0.01)
    }

    func testCancelWhileCameraStartAwaitingDoesNotResurrectSession() async throws {
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let presence = FakePresenceMonitor()
        presence.startDelayNanoseconds = 80_000_000
        let coordinator = makeCoordinator(lock: lock, presence: presence)

        let config = try cameraConfig()
        let startTask = Task {
            try await coordinator.start(configuration: config, calibration: .defaultCentered)
        }

        // Wait until presence.start has begun awaiting
        try? await Task.sleep(nanoseconds: 20_000_000)
        await coordinator.endEarly()

        do {
            try await startTask.value
            XCTFail("Expected startCancelled")
        } catch let err as CoordinatorError {
            XCTAssertEqual(err, .startCancelled)
        }

        XCTAssertNil(coordinator.snapshot)
        XCTAssertGreaterThanOrEqual(presence.stopCount, 1)
    }

    func testLateOldGenerationIsIgnored() async throws {
        let clock = FakeClock(monotonicSeconds: 0)
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let presence = FakePresenceMonitor()
        let coordinator = makeCoordinator(clock: clock, lock: lock, presence: presence)

        // Session 1
        try await coordinator.start(configuration: try cameraConfig(), calibration: .defaultCentered)
        let gen1 = try XCTUnwrap(presence.lastStartedGeneration)
        await coordinator.endEarly()
        coordinator.clearCompletedSummary()

        // Session 2
        clock.advance(by: 10)
        try await coordinator.start(configuration: try cameraConfig(), calibration: .defaultCentered)
        let gen2 = try XCTUnwrap(presence.lastStartedGeneration)
        XCTAssertNotEqual(gen1, gen2)

        try? await Task.sleep(nanoseconds: 20_000_000)

        // Emit stale-generation absent sample for gen1 -> must NOT affect gen2
        presence.emit(PresenceSample(sequence: 1, capturedMonotonicSeconds: 10, value: .absent), generation: gen1)
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(coordinator.snapshot?.presence, .unknown(.warmingUp))

        await coordinator.endEarly()
    }

    func testSlowSaveCannotOverwriteCompletion() async throws {
        let clock = FakeClock(monotonicSeconds: 0)
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let presence = FakePresenceMonitor()
        let repo = MockSessionRepository()
        let coordinator = makeCoordinator(clock: clock, lock: lock, presence: presence, repo: repo)

        try await coordinator.start(configuration: try timerConfig(seconds: 120), calibration: nil)
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Slow down saves during active checkpoint & completion
        await repo.setSaveDelay(80_000_000)
        clock.advance(by: 6)
        coordinator.receiveActivity(.inactive) // triggers checkpoint save
        clock.advance(by: 120)
        coordinator.receiveActivity(.active)   // hits deadline & completes

        try? await Task.sleep(nanoseconds: 250_000_000)

        let id = try XCTUnwrap(coordinator.lastCompletedRecord?.id)
        let storedRecord = await repo.stored[id]
        XCTAssertEqual(storedRecord?.status, .completed)
        XCTAssertEqual(storedRecord?.revision, coordinator.lastCompletedRecord?.revision)
    }
}
