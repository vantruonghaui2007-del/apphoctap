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

    func testInjectedThermalCriticalEndsSessionAndStopsCamera() async throws {
        let clock = FakeClock(monotonicSeconds: 0)
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let presence = FakePresenceMonitor()
        let repo = MockSessionRepository()
        let idle = FakeIdleTimerController()
        let coordinator = makeCoordinator(clock: clock, lock: lock, presence: presence, repo: repo, idle: idle)

        try await coordinator.start(configuration: try cameraConfig(), calibration: .defaultCentered)
        let gen = try XCTUnwrap(presence.lastStartedGeneration)
        try? await Task.sleep(nanoseconds: 20_000_000)

        clock.advance(by: 12)
        presence.emit(PresenceSample(sequence: 1, capturedMonotonicSeconds: 12, value: .unknown(.thermal)), generation: gen)
        try? await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(coordinator.lastCompletedRecord?.status, .endedEarly(.thermalLimit))
        XCTAssertGreaterThanOrEqual(presence.stopCount, 1)
        XCTAssertFalse(idle.isAwakeDisabled)
    }

    func testCameraRevokedOnResumeMarksCameraUnavailableWithoutTrapping() async throws {
        let clock = FakeClock(monotonicSeconds: 0)
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let presence = FakePresenceMonitor()
        let repo = MockSessionRepository()
        let coordinator = makeCoordinator(clock: clock, lock: lock, presence: presence, repo: repo)

        try await coordinator.start(configuration: try cameraConfig(seconds: 180), calibration: .defaultCentered)
        clock.advance(by: 10)
        coordinator.receiveActivity(.inactive)
        try? await Task.sleep(nanoseconds: 30_000_000)

        // Simulate user revoking camera permission while app was inactive
        presence.errorOnStart = PresenceMonitorError.permissionDenied
        clock.advance(by: 15)
        coordinator.receiveActivity(.active)
        try? await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(coordinator.snapshot?.status, .running)
        XCTAssertEqual(coordinator.snapshot?.presence, .unknown(.cameraUnavailable))

        // Session still ends cleanly when user chooses
        await coordinator.endEarly()
        XCTAssertEqual(coordinator.lastCompletedRecord?.status, .endedEarly(.userEnded))
    }

    func testMidSessionStorageFailureEndsEarlyWithWarning() async throws {
        enum FakeIOError: Error { case diskFull }
        let clock = FakeClock(monotonicSeconds: 0)
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let presence = FakePresenceMonitor()
        let repo = MockSessionRepository()
        let coordinator = makeCoordinator(clock: clock, lock: lock, presence: presence, repo: repo)

        try await coordinator.start(configuration: try timerConfig(seconds: 180), calibration: nil)
        try? await Task.sleep(nanoseconds: 20_000_000)

        await repo.setErrorOnSave(FakeIOError.diskFull)
        clock.advance(by: 10)
        coordinator.receiveActivity(.inactive) // triggers checkpoint save which fails
        try? await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertEqual(coordinator.lastCompletedRecord?.status, .endedEarly(.storageFailure))
        XCTAssertNotNil(coordinator.persistenceWarningMessage)
    }

    func testTwentyFourHourWallClockJumpDuringCoordinatorSession() async throws {
        let clock = FakeClock(monotonicSeconds: 0)
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let presence = FakePresenceMonitor()
        let repo = MockSessionRepository()
        let coordinator = makeCoordinator(clock: clock, lock: lock, presence: presence, repo: repo)

        try await coordinator.start(configuration: try timerConfig(seconds: 120), calibration: nil)
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Jump wall date -24h and +24h while monotonic advances 30s
        clock.advance(by: 30, wallOffset: -86_400)
        coordinator.receiveActivity(.inactive)
        clock.advance(by: 30, wallOffset: 172_800)
        coordinator.receiveActivity(.active)
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(coordinator.snapshot?.elapsedSeconds ?? -1, 60, accuracy: 0.1)
        XCTAssertEqual(coordinator.snapshot?.remainingSeconds ?? -1, 60, accuracy: 0.1)
        await coordinator.endEarly()
    }

    func testResumeCameraStartSuspendedThenEndEarlyLeavesCameraStopped() async throws {
        let clock = FakeClock(monotonicSeconds: 0)
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let presence = FakePresenceMonitor()
        let repo = MockSessionRepository()
        let coordinator = makeCoordinator(clock: clock, lock: lock, presence: presence, repo: repo)

        try await coordinator.start(configuration: try cameraConfig(), calibration: .defaultCentered)
        let firstToken = try XCTUnwrap(presence.lastStartedGeneration)
        XCTAssertTrue(presence.isCapturing)

        clock.advance(by: 5)
        coordinator.receiveActivity(.inactive)
        try? await Task.sleep(nanoseconds: 25_000_000)
        XCTAssertFalse(presence.isCapturing)

        // Suspend the resume camera start
        presence.suspendNextStart()
        clock.advance(by: 5)
        coordinator.receiveActivity(.active)
        await presence.waitUntilStartSuspended()

        // End session early while resume start is still awaiting
        await coordinator.endEarly()

        // Complete the delayed camera start AFTER session ended
        presence.resumeSuspendedStart()
        try? await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertFalse(presence.isCapturing, "Camera must NOT stay running after session ended")
        XCTAssertEqual(coordinator.lastCompletedRecord?.status, .endedEarly(.userEnded))
        XCTAssertEqual(presence.startedGenerations.count, 2)
        XCTAssertNotEqual(firstToken, presence.startedGenerations[1])
    }

    func testResumeCameraStartSuspendedThenInactiveStopsCameraAndUsesNewRunToken() async throws {
        let clock = FakeClock(monotonicSeconds: 0)
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let presence = FakePresenceMonitor()
        let repo = MockSessionRepository()
        let coordinator = makeCoordinator(clock: clock, lock: lock, presence: presence, repo: repo)

        try await coordinator.start(configuration: try cameraConfig(seconds: 180), calibration: .defaultCentered)
        let token1 = try XCTUnwrap(presence.lastStartedGeneration)
        try? await Task.sleep(nanoseconds: 20_000_000)

        clock.advance(by: 5)
        coordinator.receiveActivity(.inactive)
        try? await Task.sleep(nanoseconds: 25_000_000)

        // Suspend resume start, then go inactive again while it's pending
        presence.suspendNextStart()
        clock.advance(by: 5)
        coordinator.receiveActivity(.active)
        await presence.waitUntilStartSuspended()

        coordinator.receiveActivity(.inactive)
        presence.resumeSuspendedStart()
        try? await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertFalse(presence.isCapturing, "Camera must stop when app returned inactive during pending resume")

        // Resume cleanly -> gets a third run token; late frame from token1 must be ignored
        clock.advance(by: 5)
        coordinator.receiveActivity(.active)
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertTrue(presence.isCapturing)
        let token3 = try XCTUnwrap(presence.lastStartedGeneration)
        XCTAssertNotEqual(token1, token3)

        presence.emit(PresenceSample(sequence: 1, capturedMonotonicSeconds: 15, value: .absent), generation: token1)
        try? await Task.sleep(nanoseconds: 25_000_000)
        XCTAssertEqual(coordinator.snapshot?.presence, .unknown(.warmingUp))

        await coordinator.endEarly()
    }

    func testInactiveDuringPendingStartCancelsStartWithoutFakeRunningOrCamera() async throws {
        let clock = FakeClock(monotonicSeconds: 0)
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let presence = FakePresenceMonitor()
        let repo = MockSessionRepository()
        let idle = FakeIdleTimerController()
        let coordinator = makeCoordinator(clock: clock, lock: lock, presence: presence, repo: repo, idle: idle)

        // Case 1: Inactive while camera start is suspended
        presence.suspendNextStart()
        let cfg = try cameraConfig()
        let task1 = Task {
            try await coordinator.start(configuration: cfg, calibration: .defaultCentered)
        }
        await presence.waitUntilStartSuspended()
        coordinator.receiveActivity(.inactive)
        presence.resumeSuspendedStart()

        do {
            try await task1.value
            XCTFail("Expected startCancelled when app became inactive during camera start")
        } catch let err as CoordinatorError {
            XCTAssertEqual(err, .startCancelled)
        }
        XCTAssertNil(coordinator.snapshot)
        XCTAssertFalse(presence.isCapturing)
        XCTAssertFalse(idle.isAwakeDisabled)

        // Case 2: Return active, then go background while initial save is delayed
        coordinator.receiveActivity(.active)
        await repo.setSaveDelay(80_000_000)
        let timerCfg = try timerConfig()
        let task2 = Task {
            try await coordinator.start(configuration: timerCfg, calibration: nil)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        coordinator.receiveActivity(.background)

        do {
            try await task2.value
            XCTFail("Expected startCancelled when app entered background during initial save")
        } catch let err as CoordinatorError {
            XCTAssertEqual(err, .startCancelled)
        }
        XCTAssertNil(coordinator.snapshot)
        XCTAssertFalse(idle.isAwakeDisabled)
    }
}
