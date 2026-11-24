import Foundation
import Combine
import StudyCore

@MainActor
public final class SessionViewModel: ObservableObject {
    @Published public private(set) var snapshot: SessionSnapshot?
    @Published public private(set) var activeConfiguration: SessionConfiguration?
    @Published public private(set) var lastCompletedRecord: SessionRecord?
    @Published public private(set) var persistenceWarningMessage: String?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isGuidedAccessEnabled: Bool = false
    @Published public private(set) var isFinalizing: Bool = false

    public let coordinator: SessionCoordinator
    private let lockMonitor: GuidedAccessMonitoring
    private var cancellables = Set<AnyCancellable>()
    private var lockTask: Task<Void, Never>?

    public init(coordinator: SessionCoordinator, lockMonitor: GuidedAccessMonitoring) {
        self.coordinator = coordinator
        self.lockMonitor = lockMonitor
        self.isGuidedAccessEnabled = lockMonitor.isEnabled

        coordinator.$snapshot
            .assign(to: &$snapshot)
        coordinator.$activeConfiguration
            .assign(to: &$activeConfiguration)
        coordinator.$lastCompletedRecord
            .assign(to: &$lastCompletedRecord)
        coordinator.$persistenceWarningMessage
            .assign(to: &$persistenceWarningMessage)
        coordinator.$lastErrorMessage
            .assign(to: &$errorMessage)
        coordinator.$isFinalizing
            .assign(to: &$isFinalizing)

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

    public func refreshLockStatus() {
        isGuidedAccessEnabled = lockMonitor.isEnabled
    }

    public func startSession(configuration: SessionConfiguration, calibration: Calibration?) async -> Bool {
        refreshLockStatus()
        errorMessage = nil
        do {
            try await coordinator.start(configuration: configuration, calibration: calibration)
            return true
        } catch CoordinatorError.previousSessionFinalizing {
            errorMessage = "Đang hoàn tất dọn dẹp phiên học trước, vui lòng đợi trong giây lát."
            return false
        } catch CoordinatorError.guidedAccessRequired {
            errorMessage = "Hãy bật Guided Access trên iPhone trước khi bắt đầu phiên học nghiêm."
            return false
        } catch CoordinatorError.calibrationRequired {
            errorMessage = "Cần hiệu chỉnh camera trước khi dùng chế độ xác nhận hiện diện."
            return false
        } catch PresenceMonitorError.permissionDenied, PresenceMonitorError.permissionRestricted {
            errorMessage = "Chưa có quyền camera. Bạn có thể chuyển sang chế độ Chỉ đồng hồ hoặc cấp quyền trong Cài đặt."
            return false
        } catch PresenceMonitorError.cameraUnavailable {
            errorMessage = "Camera không khả dụng. Hãy chuyển sang chế độ Chỉ đồng hồ."
            return false
        } catch PresenceMonitorError.thermalCritical, CoordinatorError.thermalCritical {
            errorMessage = "Thiết bị đang quá nóng, tạm thời không thể dùng camera. Hãy để máy nguội hoặc chuyển sang chế độ Chỉ đồng hồ."
            return false
        } catch CoordinatorError.startCancelled {
            return false
        } catch {
            errorMessage = "Không thể khởi tạo phiên học hoặc lưu dữ liệu ban đầu lên máy."
            return false
        }
    }

    public func endEarly() async {
        await coordinator.endEarly()
    }

    public func resetSummary() {
        coordinator.clearCompletedSummary()
    }
}

