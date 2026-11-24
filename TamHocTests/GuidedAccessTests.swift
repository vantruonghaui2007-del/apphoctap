import XCTest
import StudyCore
@testable import TamHoc

@MainActor
final class GuidedAccessTests: XCTestCase {
    func testMonitorReadsInitialSystemStatus() {
        let enabledMonitor = GuidedAccessMonitor(statusProvider: { true }, observeForTest: true)
        let disabledMonitor = GuidedAccessMonitor(statusProvider: { false }, observeForTest: true)

        XCTAssertTrue(enabledMonitor.isEnabled)
        XCTAssertFalse(disabledMonitor.isEnabled)
    }

    func testStatusNotificationRereadsBoolean() async {
        var systemValue = false
        let center = NotificationCenter()
        let noteName = Notification.Name("TestGuidedAccessChanged")
        let monitor = GuidedAccessMonitor(
            statusProvider: { systemValue },
            notificationCenter: center,
            notificationName: noteName
        )

        var iterator = monitor.changes.makeAsyncIterator()

        // Notification with unchanged underlying boolean must NOT blindly toggle
        center.post(name: noteName, object: nil)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(monitor.isEnabled)

        // Flip system boolean and post notification -> emits true
        systemValue = true
        center.post(name: noteName, object: nil)
        let first = await iterator.next()
        XCTAssertEqual(first, true)
        XCTAssertTrue(monitor.isEnabled)

        // Flip back to false and post -> emits false
        systemValue = false
        center.post(name: noteName, object: nil)
        let second = await iterator.next()
        XCTAssertEqual(second, false)
        XCTAssertFalse(monitor.isEnabled)
    }

    private func awaitFirstStreamValue(
        from monitor: GuidedAccessMonitor,
        timeoutNanoseconds: UInt64,
        afterSubscribing action: () -> Void
    ) async -> Bool? {
        let stream = monitor.changes
        XCTAssertEqual(monitor.subscriberCountForTesting, 1)
        action()

        let readerTask = Task { @MainActor () -> Bool? in
            for await value in stream {
                return value
            }
            return nil
        }

        return await BoundedAsyncWaiter.waitForTask(
            readerTask,
            timeoutNanoseconds: timeoutNanoseconds,
            onTimeout: {
                readerTask.cancel()
            }
        )
    }

    func testReadingIsEnabledBeforeNotificationDoesNotDropChangeEvent() async throws {
        var systemValue = true
        let center = NotificationCenter()
        let noteName = Notification.Name("TestGuidedAccessReadRace")
        let monitor = GuidedAccessMonitor(
            statusProvider: { systemValue },
            notificationCenter: center,
            notificationName: noteName
        )

        let result = await awaitFirstStreamValue(
            from: monitor,
            timeoutNanoseconds: 1_000_000_000
        ) {
            // Flip system status and read isEnabled BEFORE notification runs
            systemValue = false
            XCTAssertFalse(monitor.isEnabled)
            center.post(name: noteName, object: nil)
        }

        XCTAssertEqual(result, false)
        for _ in 0..<20 where monitor.subscriberCountForTesting > 0 {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(monitor.subscriberCountForTesting, 0)
    }

    func testStreamWaitTimeoutExitsPromptlyAndCleansUpSubscriberWhenNoNotificationPosted() async {
        let systemClock = SystemSessionClock()
        let monitor = GuidedAccessMonitor(
            statusProvider: { true },
            notificationCenter: NotificationCenter(),
            notificationName: Notification.Name("TestNeverPostedGuidedAccess")
        )

        let start = systemClock.now().monotonicSeconds
        let result = await awaitFirstStreamValue(
            from: monitor,
            timeoutNanoseconds: 150_000_000
        ) {
            // Deliberately do NOT post any notification
        }
        let elapsed = systemClock.now().monotonicSeconds - start

        XCTAssertNil(result)
        XCTAssertLessThan(elapsed, 1.5, "Timeout helper must exit within bounded duration without hanging")

        for _ in 0..<20 where monitor.subscriberCountForTesting > 0 {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(monitor.subscriberCountForTesting, 0, "Structured cancellation must remove stream subscriber")
    }

    func testDuplicateLifecycleEventsAreCoalesced() async {
        let center = NotificationCenter()
        let monitor = AppActivityMonitor(
            initialState: .active,
            notificationCenter: center,
            observeSystemNotifications: true
        )

        var received: [ActivityState] = []
        let task = Task {
            for await state in monitor.changes {
                received.append(state)
                if received.count >= 3 { break }
            }
        }

        // Let stream subscribe
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Duplicate inactive reports from both UIKit and ScenePhase coalesce into 1
        monitor.report(.inactive)
        monitor.report(scenePhase: .inactive)
        center.post(name: UIApplication.willResignActiveNotification, object: nil)

        monitor.report(.background)
        monitor.report(scenePhase: .background)

        monitor.report(.active)
        monitor.report(scenePhase: .active)

        _ = await task.value
        XCTAssertEqual(received, [.inactive, .background, .active])
    }

    func testUnknownDestinationIsNotLabeledTikTok() throws {
        let cfg = try SessionConfiguration.validated(
            plannedSeconds: 120,
            presenceMode: .timerOnly,
            warningsEnabled: true
        )
        var engine = SessionEngine(
            id: UUID(),
            configuration: cfg,
            startedAt: TimePoint(monotonicSeconds: 0, wallDate: Date())
        )
        _ = try engine.handle(.activityChanged(.inactive), at: TimePoint(monotonicSeconds: 5, wallDate: Date()))
        _ = try engine.handle(.activityChanged(.background), at: TimePoint(monotonicSeconds: 10, wallDate: Date()))
        _ = try engine.handle(.finish(.userEnded), at: TimePoint(monotonicSeconds: 20, wallDate: Date()))

        let data = try RepositoryJSONCoding.makeEncoder().encode(engine.record)
        let json = String(decoding: data, as: UTF8.self).lowercased()
        XCTAssertFalse(json.contains("tiktok"))
        XCTAssertFalse(json.contains("youtube"))
        XCTAssertFalse(json.contains("instagram"))
    }

    func testPreflightViewModelDeallocatesAndUnsubscribesWithoutRetainCycle() async {
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        var vm: PreflightViewModel? = PreflightViewModel(
            plannedSeconds: 300,
            presenceMode: .timerOnly,
            warningsEnabled: true,
            calibration: nil,
            lockMonitor: lock,
            cameraAuthorizer: FakeCameraAuthorizer()
        )
        weak var weakVM = vm

        // Wait for subscription task to start listening
        for _ in 0..<40 where lock.subscriberCount == 0 {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(lock.subscriberCount, 1)

        // Deliver a live event through the active stream
        lock.send(false)
        for _ in 0..<40 where vm?.isGuidedAccessEnabled == true {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(vm?.isGuidedAccessEnabled, false)

        // Drop external reference without manually calling stopObserving()
        vm = nil
        XCTAssertNil(weakVM, "PreflightViewModel must not be retained by its lock observation task")

        for _ in 0..<40 where lock.subscriberCount > 0 {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(lock.subscriberCount, 0)
    }

    func testPreflightViewModelStopObservingRemovesSubscriberOnDisappear() async {
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let vm = PreflightViewModel(
            plannedSeconds: 300,
            presenceMode: .timerOnly,
            warningsEnabled: true,
            calibration: nil,
            lockMonitor: lock,
            cameraAuthorizer: FakeCameraAuthorizer()
        )

        for _ in 0..<40 where lock.subscriberCount == 0 {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(lock.subscriberCount, 1)

        vm.stopObserving()
        for _ in 0..<40 where lock.subscriberCount > 0 {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(lock.subscriberCount, 0)
    }

    func testSessionViewModelDeallocatesWithoutRetainCycle() async {
        let lock = FakeGuidedAccessMonitor(isEnabled: true)
        let coordinator = SessionCoordinator(
            clock: FakeClock(),
            lockMonitor: lock,
            presenceMonitor: FakePresenceMonitor(),
            repository: MockSessionRepository(),
            warningPlayer: SpyWarningPlayer(),
            idleTimerController: FakeIdleTimerController(),
            backgroundTaskManager: FakeBackgroundTaskManager()
        )
        var vm: SessionViewModel? = SessionViewModel(coordinator: coordinator, lockMonitor: lock)
        weak var weakVM = vm

        for _ in 0..<40 where lock.subscriberCount == 0 {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(lock.subscriberCount, 1)

        lock.send(false)
        for _ in 0..<40 where vm?.isGuidedAccessEnabled == true {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(vm?.isGuidedAccessEnabled, false)

        vm = nil
        XCTAssertNil(weakVM, "SessionViewModel must not be retained by its lock observation task")

        for _ in 0..<40 where lock.subscriberCount > 0 {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(lock.subscriberCount, 0)
    }
}

private extension GuidedAccessMonitor {
    convenience init(statusProvider: @escaping () -> Bool, observeForTest: Bool) {
        let _ = observeForTest
        self.init(
            statusProvider: statusProvider,
            notificationCenter: NotificationCenter(),
            notificationName: Notification.Name("TestUnusedGuidedAccess")
        )
    }
}

