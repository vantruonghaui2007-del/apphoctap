import Foundation
import StudyCore
@testable import TamHoc

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
