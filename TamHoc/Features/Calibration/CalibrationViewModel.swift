import Foundation
import AVFoundation
import CoreGraphics
import StudyCore

public enum CalibrationStep: Int, CaseIterable, Equatable {
    case sitUpright = 0
    case leanToWrite = 1
    case stepAway = 2

    public var title: String {
        switch self {
        case .sitUpright: return "Bước 1/3: Ngồi học bình thường (5 giây)"
        case .leanToWrite: return "Bước 2/3: Cúi đầu viết bài (5 giây)"
        case .stepAway: return "Bước 3/3: Rời khỏi bàn học (5 giây)"
        }
    }

    public var instruction: String {
        switch self {
        case .sitUpright:
            return "Ngồi thẳng tự nhiên trong khung hình đã chọn."
        case .leanToWrite:
            return "Cúi đầu viết như khi làm bài tập để đảm bảo app không báo nhầm."
        case .stepAway:
            return "Đứng lên rời khỏi tầm nhìn camera để kiểm tra nhận diện vắng mặt."
        }
    }
}

public enum CalibrationRunState: Equatable {
    case idle
    case running(step: CalibrationStep, secondsLeft: Int)
    case passed(Calibration)
    case failed(String)
}

@MainActor
public final class CalibrationViewModel: ObservableObject {
    @Published public private(set) var runState: CalibrationRunState = .idle
    @Published public private(set) var livePresence: PresenceValue = .unknown(.warmingUp)
    @Published public private(set) var confusionSummary: String = ""
    @Published public var roiNormalizedPreviewRect: CGRect = CGRect(x: 0.15, y: 0.10, width: 0.70, height: 0.75)

    private let presenceMonitor: PresenceMonitoring
    private let settingsRepository: SettingsRepository
    private var calibrationTask: Task<Void, Never>?
    private var listenerTask: Task<Void, Never>?
    private var stepCounts: [CalibrationStep: (present: Int, absent: Int, unknown: Int)] = [:]
    private var currentStep: CalibrationStep?

    public init(
        presenceMonitor: PresenceMonitoring,
        settingsRepository: SettingsRepository
    ) {
        self.presenceMonitor = presenceMonitor
        self.settingsRepository = settingsRepository
    }

    public var previewSession: AVCaptureSession? {
        (presenceMonitor as? CameraPresenceMonitor)?.previewCaptureSession
    }

    public func startCalibration(previewBounds: CGRect, imageSize: CGSize) {
        cancel()
        stepCounts = [:]
        confusionSummary = ""

        let candidateCalibration: Calibration
        do {
            let rectInPreview = CGRect(
                x: previewBounds.minX + roiNormalizedPreviewRect.minX * previewBounds.width,
                y: previewBounds.minY + roiNormalizedPreviewRect.minY * previewBounds.height,
                width: roiNormalizedPreviewRect.width * previewBounds.width,
                height: roiNormalizedPreviewRect.height * previewBounds.height
            )
            if previewBounds.width > 0, previewBounds.height > 0 {
                candidateCalibration = try PreviewGeometry.visionROI(
                    fromPreviewRect: rectInPreview,
                    previewBounds: previewBounds,
                    imageSize: imageSize,
                    mirrored: true
                )
            } else {
                candidateCalibration = .defaultCentered
            }
        } catch {
            runState = .failed("Khung hiệu chỉnh không hợp lệ. Vui lòng thử lại.")
            return
        }

        let generation = UUID()
        calibrationTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.presenceMonitor.start(calibration: candidateCalibration, generation: generation)
            } catch let err as PresenceMonitorError {
                switch err {
                case .permissionDenied, .permissionRestricted:
                    self.runState = .failed("Chưa có quyền camera. Bạn có thể cấp quyền trong Cài đặt iOS hoặc chuyển sang chế độ Chỉ đồng hồ.")
                case .cameraUnavailable:
                    self.runState = .failed("Camera trước không khả dụng trên thiết bị này. Hãy dùng chế độ Chỉ đồng hồ.")
                }
                return
            } catch {
                self.runState = .failed("Không thể khởi động camera hiệu chỉnh.")
                return
            }

            self.listenerTask = Task { [weak self] in
                guard let self = self else { return }
                for await event in self.presenceMonitor.events {
                    guard event.generation == generation, !Task.isCancelled else { continue }
                    self.livePresence = event.sample.value
                    if let step = self.currentStep {
                        var counts = self.stepCounts[step] ?? (0, 0, 0)
                        switch event.sample.value {
                        case .present: counts.present += 1
                        case .absent: counts.absent += 1
                        case .unknown: counts.unknown += 1
                        }
                        self.stepCounts[step] = counts
                    }
                }
            }

            for step in CalibrationStep.allCases {
                if Task.isCancelled { break }
                self.currentStep = step
                for second in stride(from: 5, through: 1, by: -1) {
                    if Task.isCancelled { break }
                    self.runState = .running(step: step, secondsLeft: second)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            self.currentStep = nil
            self.listenerTask?.cancel()
            await self.presenceMonitor.stop()

            guard !Task.isCancelled else { return }
            await self.evaluateAndPersist(calibration: candidateCalibration)
        }
    }

    public func cancel() {
        calibrationTask?.cancel()
        calibrationTask = nil
        listenerTask?.cancel()
        listenerTask = nil
        currentStep = nil
        Task {
            await presenceMonitor.stop()
        }
        if case .running = runState {
            runState = .idle
            livePresence = .unknown(.warmingUp)
        }
    }

    private func evaluateAndPersist(calibration: Calibration) async {
        let sit = stepCounts[.sitUpright] ?? (0, 0, 0)
        let write = stepCounts[.leanToWrite] ?? (0, 0, 0)
        let away = stepCounts[.stepAway] ?? (0, 0, 0)

        confusionSummary = "Ngồi: \(sit.present) có / \(sit.absent) vắng • Cúi viết: \(write.present) có / \(write.absent) vắng • Rời chỗ: \(away.absent) vắng / \(away.present) có"

        let sitPassed = sit.present >= 2 && sit.present > sit.absent
        let writePassed = write.present >= 2 && write.present >= write.absent
        let awayPassed = away.absent >= 2 && away.absent > away.present

        guard sitPassed && writePassed && awayPassed else {
            var reasons: [String] = []
            if !sitPassed { reasons.append("chưa nhận diện rõ khi ngồi thẳng") }
            if !writePassed { reasons.append("dễ mất nhận diện khi cúi viết") }
            if !awayPassed { reasons.append("chưa phân biệt rõ lúc rời bàn") }
            runState = .failed("Hiệu chỉnh chưa đạt (\(reasons.joined(separator: ", "))). Hãy đặt máy cao hơn, đủ ánh sáng hoặc chuyển sang chế độ Chỉ đồng hồ.")
            return
        }

        do {
            try await settingsRepository.saveCalibration(calibration)
            self.runState = .passed(calibration)
        } catch {
            self.runState = .failed("Hiệu chỉnh đạt nhưng không lưu được thông số ROI lên máy.")
        }
    }
}
