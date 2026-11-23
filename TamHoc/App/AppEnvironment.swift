import Foundation
import StudyCore

@MainActor
final class AppEnvironment: ObservableObject {
    let guidedAccessMonitor: GuidedAccessMonitoring

    static var isUITestHarnessEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uitest")
        #else
        return false
        #endif
    }

    init(guidedAccessMonitor: GuidedAccessMonitoring? = nil) {
        if let guidedAccessMonitor = guidedAccessMonitor {
            self.guidedAccessMonitor = guidedAccessMonitor
        } else {
            self.guidedAccessMonitor = GuidedAccessMonitor()
        }
    }
}
