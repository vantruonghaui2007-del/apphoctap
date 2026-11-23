import Foundation
import StudyCore

@MainActor
final class AppEnvironment: ObservableObject {
    let clock: SessionClock
    let guidedAccessMonitor: GuidedAccessMonitoring
    let activityMonitor: AppActivityMonitor
    let cameraAuthorizer: CameraAuthorizing
    let presenceMonitor: PresenceMonitoring
    let sessionRepository: SessionRepository
    let settingsRepository: SettingsRepository
    let warningPlayer: WarningPlayer
    let coordinator: SessionCoordinator
    let sessionViewModel: SessionViewModel

    @Published var settings: AppSettings = .default
    @Published var calibration: Calibration?
    @Published var settingsLoadErrorMessage: String?
    @Published var didFinishBootstrap = false

    static var isUITestHarnessEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uitest")
        #else
        return false
        #endif
    }

    init() {
        #if DEBUG
        if Self.isUITestHarnessEnabled {
            let uiTestEnv = Self.makeDebugUITestEnvironment(arguments: ProcessInfo.processInfo.arguments)
            self.clock = uiTestEnv.clock
            self.guidedAccessMonitor = uiTestEnv.lockMonitor
            self.activityMonitor = AppActivityMonitor(initialState: .active, observeSystemNotifications: false)
            self.cameraAuthorizer = uiTestEnv.cameraAuthorizer
            self.presenceMonitor = uiTestEnv.presenceMonitor
            self.sessionRepository = uiTestEnv.sessionRepository
            self.settingsRepository = uiTestEnv.settingsRepository
            self.warningPlayer = uiTestEnv.warningPlayer
            self.coordinator = uiTestEnv.coordinator
            self.sessionViewModel = SessionViewModel(coordinator: uiTestEnv.coordinator, lockMonitor: uiTestEnv.lockMonitor)
            self.settings = uiTestEnv.initialSettings
            self.didFinishBootstrap = true
            return
        }
        #endif

        let clock = SystemSessionClock()
        let lockMonitor = GuidedAccessMonitor()
        let activityMonitor = AppActivityMonitor()
        let cameraAuthorizer = SystemCameraAuthorizer()
        let presenceMonitor = CameraPresenceMonitor(clock: clock, authorizer: cameraAuthorizer)
        let sessionRepository = FileSessionRepository(directory: FileSessionRepository.defaultSessionsDirectory())
        let settingsRepository = SettingsRepository(directory: SettingsRepository.defaultDirectory())
        let warningPlayer = WarningPlayer()

        let coordinator = SessionCoordinator(
            clock: clock,
            lockMonitor: lockMonitor,
            presenceMonitor: presenceMonitor,
            repository: sessionRepository,
            warningPlayer: warningPlayer
        )

        self.clock = clock
        self.guidedAccessMonitor = lockMonitor
        self.activityMonitor = activityMonitor
        self.cameraAuthorizer = cameraAuthorizer
        self.presenceMonitor = presenceMonitor
        self.sessionRepository = sessionRepository
        self.settingsRepository = settingsRepository
        self.warningPlayer = warningPlayer
        self.coordinator = coordinator
        self.sessionViewModel = SessionViewModel(coordinator: coordinator, lockMonitor: lockMonitor)

        warningPlayer.updateWarningsEnabledProvider { [weak self] in
            self?.settings.warningsEnabled ?? true
        }
    }

    func bootstrap() async {
        guard !didFinishBootstrap else { return }

        do {
            self.settings = try await settingsRepository.loadSettings()
        } catch {
            self.settingsLoadErrorMessage = "Không đọc được tệp cài đặt đã lưu; giữ nguyên tệp trên máy."
        }

        do {
            self.calibration = try await settingsRepository.loadCalibration()
        } catch {
            self.calibration = nil
        }

        try? await coordinator.recoverUnfinishedSessions()
        try? await RetentionPolicy.pruneRepository(sessionRepository)
        self.didFinishBootstrap = true
    }

    func markOnboardingSeen() async {
        var updated = settings
        updated.onboardingVersionSeen = AppSettings.currentOnboardingVersion
        settings = updated
        try? await settingsRepository.saveSettings(updated)
    }
}

#if DEBUG
private extension AppEnvironment {
    struct DebugHarness {
        let clock: SessionClock
        let lockMonitor: GuidedAccessMonitoring
        let cameraAuthorizer: CameraAuthorizing
        let presenceMonitor: PresenceMonitoring
        let sessionRepository: SessionRepository
        let settingsRepository: SettingsRepository
        let warningPlayer: WarningPlayer
        let coordinator: SessionCoordinator
        let initialSettings: AppSettings
    }

    static func makeDebugUITestEnvironment(arguments: [String]) -> DebugHarness {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TamHocUITest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        let lockEnabled = arguments.contains("-uitest-lock-on")
        let lockMonitor = GuidedAccessMonitor(
            statusProvider: { lockEnabled },
            notificationCenter: NotificationCenter(),
            notificationName: Notification.Name("UITestGuidedAccessUnused")
        )

        let cameraDenied = arguments.contains("-uitest-camera-denied")
        let authorizer = UITestCameraAuthorizer(denied: cameraDenied)
        let clock = SystemSessionClock()
        let presenceMonitor = CameraPresenceMonitor(
            clock: clock,
            authorizer: authorizer,
            detector: VisionPersonDetector()
        )
        let sessionRepository = FileSessionRepository(directory: testDir.appendingPathComponent("Sessions", isDirectory: true))
        let settingsRepository = SettingsRepository(directory: testDir)
        let warningPlayer = WarningPlayer()

        let skipOnboarding = !arguments.contains("-uitest-show-onboarding")
        var initialSettings = AppSettings.default
        if skipOnboarding {
            initialSettings.onboardingVersionSeen = AppSettings.currentOnboardingVersion
            let data = try? RepositoryJSONCoding.makeEncoder().encode(initialSettings)
            if let data = data {
                try? data.write(to: testDir.appendingPathComponent("settings.json"))
            }
        }

        let coordinator = SessionCoordinator(
            clock: clock,
            lockMonitor: lockMonitor,
            presenceMonitor: presenceMonitor,
            repository: sessionRepository,
            warningPlayer: warningPlayer
        )

        return DebugHarness(
            clock: clock,
            lockMonitor: lockMonitor,
            cameraAuthorizer: authorizer,
            presenceMonitor: presenceMonitor,
            sessionRepository: sessionRepository,
            settingsRepository: settingsRepository,
            warningPlayer: warningPlayer,
            coordinator: coordinator,
            initialSettings: initialSettings
        )
    }

    struct UITestCameraAuthorizer: CameraAuthorizing {
        let denied: Bool
        func authorizationStatus() -> CameraAuthorizationState { denied ? .denied : .authorized }
        func requestAccess() async -> Bool { !denied }
        func hasFrontCamera() -> Bool { !denied }
    }
}
#endif
