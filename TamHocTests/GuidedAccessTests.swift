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
