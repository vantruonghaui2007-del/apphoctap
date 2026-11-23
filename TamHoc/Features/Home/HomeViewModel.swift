import Foundation
import StudyCore

@MainActor
public final class HomeViewModel: ObservableObject {
    public static let presetMinutes: [Int] = [25, 50, 90]

    @Published public var selectedMinutes: Int
    @Published public var cameraEnabled: Bool
    @Published public var warningsEnabled: Bool

    public init(settings: AppSettings) {
        self.selectedMinutes = Int((settings.defaultDurationSeconds / 60.0).rounded())
        self.cameraEnabled = (settings.defaultPresenceMode == .cameraVerified)
        self.warningsEnabled = settings.warningsEnabled
    }

    public func syncFromSettings(_ settings: AppSettings) {
        self.selectedMinutes = Int((settings.defaultDurationSeconds / 60.0).rounded())
        self.cameraEnabled = (settings.defaultPresenceMode == .cameraVerified)
        self.warningsEnabled = settings.warningsEnabled
    }

    public var presenceMode: PresenceMode {
        cameraEnabled ? .cameraVerified : .timerOnly
    }

    public func buildConfiguration() throws -> SessionConfiguration {
        try SessionConfiguration.validated(
            plannedSeconds: Double(selectedMinutes) * 60.0,
            presenceMode: presenceMode,
            warningsEnabled: warningsEnabled
        )
    }
}
