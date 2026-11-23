import Foundation
import StudyCore

@MainActor
public final class PreflightViewModel: ObservableObject {
    @Published public var presenceMode: PresenceMode
    @Published public var calibration: Calibration?
    @Published public private(set) var cameraAuthState: CameraAuthorizationState
    @Published public private(set) var hasFrontCamera: Bool
    @Published public private(set) var isGuidedAccessEnabled: Bool
    @Published public var isStarting = false
    @Published public var statusError: String?

    private let plannedSeconds: Double
    private let warningsEnabled: Bool
    private let lockMonitor: GuidedAccessMonitoring
    private let cameraAuthorizer: CameraAuthorizing
    private var lockTask: Task<Void, Never>?

    public init(
        plannedSeconds: Double,
        presenceMode: PresenceMode,
        warningsEnabled: Bool,
        calibration: Calibration?,
        lockMonitor: GuidedAccessMonitoring,
        cameraAuthorizer: CameraAuthorizing = SystemCameraAuthorizer()
    ) {
        self.plannedSeconds = plannedSeconds
        self.presenceMode = presenceMode
        self.warningsEnabled = warningsEnabled
        self.calibration = calibration
        self.lockMonitor = lockMonitor
        self.cameraAuthorizer = cameraAuthorizer
        self.cameraAuthState = cameraAuthorizer.authorizationStatus()
        self.hasFrontCamera = cameraAuthorizer.hasFrontCamera()
        self.isGuidedAccessEnabled = lockMonitor.isEnabled

        startObserving()
    }

    deinit {
        lockTask?.cancel()
    }

    public func startObserving() {
        guard lockTask == nil else { return }
        let changes = lockMonitor.changes
        lockTask = Task { [weak self] in
            for await enabled in changes {
                guard !Task.isCancelled else { break }
                guard let self = self else { break }
                self.isGuidedAccessEnabled = enabled
            }
        }
    }

    public func stopObserving() {
        lockTask?.cancel()
        lockTask = nil
    }

    public func refreshChecks() {
        isGuidedAccessEnabled = lockMonitor.isEnabled
        cameraAuthState = cameraAuthorizer.authorizationStatus()
        hasFrontCamera = cameraAuthorizer.hasFrontCamera()
    }

    public func switchToTimerOnly() {
        presenceMode = .timerOnly
        statusError = nil
    }

    public var isCameraReady: Bool {
        if presenceMode == .timerOnly { return true }
        return hasFrontCamera && cameraAuthState == .authorized && calibration != nil
    }

    public var isCameraBlockedByPermissionOrHardware: Bool {
        guard presenceMode == .cameraVerified else { return false }
        if !hasFrontCamera { return true }
        return cameraAuthState == .denied || cameraAuthState == .restricted
    }

    public var canStartSession: Bool {
        isGuidedAccessEnabled && isCameraReady && !isStarting
    }

    public func makeConfiguration() throws -> SessionConfiguration {
        try SessionConfiguration.validated(
            plannedSeconds: plannedSeconds,
            presenceMode: presenceMode,
            warningsEnabled: warningsEnabled
        )
    }
}

