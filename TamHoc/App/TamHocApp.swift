import SwiftUI
import StudyCore

@main
struct TamHocApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            Task1FeasibilityRootView(guidedAccessMonitor: environment.guidedAccessMonitor)
        }
    }
}

private struct Task1FeasibilityRootView: View {
    let guidedAccessMonitor: GuidedAccessMonitoring
    @State private var isGuidedAccessEnabled: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Tâm Học")
                .font(.largeTitle.bold())
            Text("Hỗ trợ iOS \(StudyCoreInfo.minimumSupportedIOSVersion)+")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label(
                isGuidedAccessEnabled ? "Guided Access: Đang bật" : "Guided Access: Chưa bật",
                systemImage: isGuidedAccessEnabled ? "lock.fill" : "lock.open"
            )
            .font(.headline)
            Button("Kiểm tra trạng thái Guided Access") {
                isGuidedAccessEnabled = guidedAccessMonitor.isEnabled
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .onAppear {
            isGuidedAccessEnabled = guidedAccessMonitor.isEnabled
        }
        .task {
            for await enabled in guidedAccessMonitor.changes {
                isGuidedAccessEnabled = enabled
            }
        }
    }
}
