import SwiftUI
import StudyCore

@main
struct TamHocApp: App {
    @StateObject private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootAppView(environment: environment)
                .tint(Theme.accentTeal)
                .task {
                    await environment.bootstrap()
                    for await activity in environment.activityMonitor.changes {
                        environment.coordinator.receiveActivity(activity)
                    }
                }
                .onValueChange(of: scenePhase) { newPhase in
                    environment.activityMonitor.report(scenePhase: newPhase)
                }
        }
    }
}

private enum HomeRoute: Identifiable, Hashable {
    case calibration
    case preflight
    case history
    case settings

    var id: Self { self }
}

private struct RootAppView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var sessionViewModel: SessionViewModel
    @ObservedObject private var coordinator: SessionCoordinator

    @StateObject private var homeViewModel: HomeViewModel
    @State private var activeRoute: HomeRoute?

    init(environment: AppEnvironment) {
        self.environment = environment
        self._sessionViewModel = ObservedObject(wrappedValue: environment.sessionViewModel)
        self._coordinator = ObservedObject(wrappedValue: environment.coordinator)
        self._homeViewModel = StateObject(wrappedValue: HomeViewModel(settings: environment.settings))
    }

    var body: some View {
        Group {
            if !environment.didFinishBootstrap {
                ProgressView("Đang tải...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if environment.settings.onboardingVersionSeen < AppSettings.currentOnboardingVersion {
                WelcomeSafetyView {
                    Task {
                        await environment.markOnboardingSeen()
                    }
                }
            } else if sessionViewModel.snapshot?.status == .running {
                FocusView(sessionViewModel: sessionViewModel)
            } else if let completed = sessionViewModel.lastCompletedRecord {
                CompletionView(
                    record: completed,
                    isGuidedAccessEnabled: sessionViewModel.isGuidedAccessEnabled,
                    isFinalizing: sessionViewModel.isFinalizing,
                    persistenceWarning: sessionViewModel.persistenceWarningMessage
                ) {
                    activeRoute = nil
                    sessionViewModel.resetSummary()
                }
            } else {
                AppNavigationContainer {
                    HomeView(
                        viewModel: homeViewModel,
                        calibration: environment.calibration,
                        recoveredCount: coordinator.recoveredInterruptedRecords.count,
                        quarantinedCount: coordinator.quarantinedCount,
                        settingsErrorMessage: environment.settingsLoadErrorMessage,
                        onContinueToSetup: {
                            if homeViewModel.cameraEnabled {
                                let auth = environment.cameraAuthorizer.authorizationStatus()
                                if auth == .denied || auth == .restricted || !environment.cameraAuthorizer.hasFrontCamera() {
                                    activeRoute = .preflight
                                } else if environment.calibration == nil {
                                    activeRoute = .calibration
                                } else {
                                    activeRoute = .preflight
                                }
                            } else {
                                activeRoute = .preflight
                            }
                        },
                        onOpenHistory: { activeRoute = .history },
                        onOpenSettings: { activeRoute = .settings }
                    )
                    .sheet(item: $activeRoute) { route in
                        destinationSheet(for: route)
                    }
                }
                .onAppear {
                    homeViewModel.syncFromSettings(environment.settings)
                }
                .onValueChange(of: environment.settings) { updated in
                    homeViewModel.syncFromSettings(updated)
                }
            }
        }
    }

    @ViewBuilder
    private func destinationSheet(for route: HomeRoute) -> some View {
        switch route {
        case .calibration:
            CalibrationSheetHost(
                presenceMonitor: environment.presenceMonitor,
                settingsRepository: environment.settingsRepository,
                onCalibrationPassed: { calibration in
                    environment.calibration = calibration
                    activeRoute = .preflight
                },
                onSwitchToTimerOnly: {
                    homeViewModel.cameraEnabled = false
                    activeRoute = .preflight
                },
                onClose: { activeRoute = nil }
            )

        case .preflight:
            PreflightSheetHost(
                plannedSeconds: Double(homeViewModel.selectedMinutes) * 60.0,
                presenceMode: homeViewModel.presenceMode,
                warningsEnabled: homeViewModel.warningsEnabled,
                calibration: environment.calibration,
                lockMonitor: environment.guidedAccessMonitor,
                cameraAuthorizer: environment.cameraAuthorizer,
                sessionViewModel: sessionViewModel,
                onNeedCalibration: { activeRoute = .calibration },
                onStarted: { activeRoute = nil },
                onClose: { activeRoute = nil }
            )

        case .history:
            HistorySheetHost(
                repository: environment.sessionRepository,
                onClose: { activeRoute = nil }
            )

        case .settings:
            SettingsSheetHost(
                settings: environment.settings,
                settingsRepository: environment.settingsRepository,
                sessionRepository: environment.sessionRepository,
                onSettingsUpdated: { updated in
                    environment.settings = updated
                    homeViewModel.syncFromSettings(updated)
                },
                onRecalibrate: { activeRoute = .calibration },
                onClose: { activeRoute = nil }
            )
        }
    }
}

private struct CalibrationSheetHost: View {
    @StateObject private var viewModel: CalibrationViewModel
    let onCalibrationPassed: (Calibration) -> Void
    let onSwitchToTimerOnly: () -> Void
    let onClose: () -> Void

    init(
        presenceMonitor: PresenceMonitoring,
        settingsRepository: SettingsRepository,
        onCalibrationPassed: @escaping (Calibration) -> Void,
        onSwitchToTimerOnly: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: CalibrationViewModel(
                presenceMonitor: presenceMonitor,
                settingsRepository: settingsRepository
            )
        )
        self.onCalibrationPassed = onCalibrationPassed
        self.onSwitchToTimerOnly = onSwitchToTimerOnly
        self.onClose = onClose
    }

    var body: some View {
        AppNavigationContainer {
            CalibrationView(
                viewModel: viewModel,
                onCalibrationPassed: onCalibrationPassed,
                onSwitchToTimerOnly: onSwitchToTimerOnly
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng", action: onClose)
                }
            }
        }
    }
}

private struct PreflightSheetHost: View {
    @StateObject private var viewModel: PreflightViewModel
    let sessionViewModel: SessionViewModel
    let onNeedCalibration: () -> Void
    let onStarted: () -> Void
    let onClose: () -> Void

    init(
        plannedSeconds: Double,
        presenceMode: PresenceMode,
        warningsEnabled: Bool,
        calibration: Calibration?,
        lockMonitor: GuidedAccessMonitoring,
        cameraAuthorizer: CameraAuthorizing,
        sessionViewModel: SessionViewModel,
        onNeedCalibration: @escaping () -> Void,
        onStarted: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: PreflightViewModel(
                plannedSeconds: plannedSeconds,
                presenceMode: presenceMode,
                warningsEnabled: warningsEnabled,
                calibration: calibration,
                lockMonitor: lockMonitor,
                cameraAuthorizer: cameraAuthorizer
            )
        )
        self.sessionViewModel = sessionViewModel
        self.onNeedCalibration = onNeedCalibration
        self.onStarted = onStarted
        self.onClose = onClose
    }

    var body: some View {
        AppNavigationContainer {
            PreflightView(
                viewModel: viewModel,
                onNeedCalibration: onNeedCalibration,
                onStartSession: { configuration, calibration in
                    let started = await sessionViewModel.startSession(
                        configuration: configuration,
                        calibration: calibration
                    )
                    if started {
                        onStarted()
                    } else {
                        viewModel.statusError = sessionViewModel.errorMessage
                    }
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng", action: onClose)
                }
            }
        }
    }
}

private struct HistorySheetHost: View {
    @StateObject private var viewModel: HistoryViewModel
    let onClose: () -> Void

    init(repository: SessionRepository, onClose: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: HistoryViewModel(repository: repository))
        self.onClose = onClose
    }

    var body: some View {
        AppNavigationContainer {
            HistoryView(viewModel: viewModel)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Đóng", action: onClose)
                    }
                }
        }
    }
}

private struct SettingsSheetHost: View {
    @StateObject private var viewModel: SettingsViewModel
    let sessionRepository: SessionRepository
    let onRecalibrate: () -> Void
    let onClose: () -> Void

    init(
        settings: AppSettings,
        settingsRepository: SettingsRepository,
        sessionRepository: SessionRepository,
        onSettingsUpdated: @escaping (AppSettings) -> Void,
        onRecalibrate: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: SettingsViewModel(
                settings: settings,
                settingsRepository: settingsRepository,
                onSettingsUpdated: onSettingsUpdated
            )
        )
        self.sessionRepository = sessionRepository
        self.onRecalibrate = onRecalibrate
        self.onClose = onClose
    }

    var body: some View {
        AppNavigationContainer {
            SettingsView(
                viewModel: viewModel,
                onRecalibrate: onRecalibrate,
                onClearHistory: {
                    let historyVM = HistoryViewModel(repository: sessionRepository)
                    await historyVM.load()
                    await historyVM.deleteAll()
                }
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng", action: onClose)
                }
            }
        }
    }
}
