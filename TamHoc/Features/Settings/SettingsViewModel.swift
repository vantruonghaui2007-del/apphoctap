import Foundation
import StudyCore

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var defaultMinutes: Int
    @Published public var defaultCameraEnabled: Bool
    @Published public var warningsEnabled: Bool
    @Published public private(set) var saveErrorMessage: String?

    private var currentSettings: AppSettings
    private let settingsRepository: SettingsRepository
    private let onSettingsUpdated: (AppSettings) -> Void

    public init(
        settings: AppSettings,
        settingsRepository: SettingsRepository,
        onSettingsUpdated: @escaping (AppSettings) -> Void
    ) {
        self.currentSettings = settings
        self.defaultMinutes = Int((settings.defaultDurationSeconds / 60.0).rounded())
        self.defaultCameraEnabled = (settings.defaultPresenceMode == .cameraVerified)
        self.warningsEnabled = settings.warningsEnabled
        self.settingsRepository = settingsRepository
        self.onSettingsUpdated = onSettingsUpdated
    }

    public func persist() async {
        saveErrorMessage = nil
        var updated = currentSettings
        updated.defaultDurationSeconds = Double(defaultMinutes) * 60.0
        updated.defaultPresenceMode = defaultCameraEnabled ? .cameraVerified : .timerOnly
        updated.warningsEnabled = warningsEnabled

        do {
            try await settingsRepository.saveSettings(updated)
            currentSettings = updated
            onSettingsUpdated(updated)
        } catch {
            saveErrorMessage = "Không thể lưu thay đổi cài đặt."
        }
    }
}
