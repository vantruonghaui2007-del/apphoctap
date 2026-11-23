import SwiftUI
import UIKit
import AVFoundation
import StudyCore

public struct CameraPreviewRepresentable: UIViewRepresentable {
    public let session: AVCaptureSession?

    public init(session: AVCaptureSession?) {
        self.session = session
    }

    public func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    public func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    public final class PreviewUIView: UIView {
        override public class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

public struct CalibrationView: View {
    @ObservedObject var viewModel: CalibrationViewModel
    let onCalibrationPassed: (Calibration) -> Void
    let onSwitchToTimerOnly: () -> Void

    @State private var previewSize: CGSize = CGSize(width: 300, height: 400)

    public init(
        viewModel: CalibrationViewModel,
        onCalibrationPassed: @escaping (Calibration) -> Void,
        onSwitchToTimerOnly: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onCalibrationPassed = onCalibrationPassed
        self.onSwitchToTimerOnly = onSwitchToTimerOnly
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Hiệu chỉnh vị trí học")
                    .font(.title2.bold())

                Text("Camera chỉ kiểm tra bạn có ở trong vùng khung này ngay trên thiết bị, không lưu hay gửi ảnh.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ZStack {
                    CameraPreviewRepresentable(session: viewModel.previewSession)
                        .background(Color.black.opacity(0.85))

                    GeometryReader { geo in
                        let roi = viewModel.roiNormalizedPreviewRect
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 42 / 255, green: 157 / 255, blue: 143 / 255), lineWidth: 3)
                            .frame(
                                width: roi.width * geo.size.width,
                                height: roi.height * geo.size.height
                            )
                            .position(
                                x: (roi.minX + roi.width / 2) * geo.size.width,
                                y: (roi.minY + roi.height / 2) * geo.size.height
                            )
                            .onAppear {
                                previewSize = geo.size
                            }
                    }
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Khung xem trước hiệu chỉnh camera")

                statusSection

                HStack(spacing: 12) {
                    Button("Bắt đầu hiệu chỉnh 15 giây") {
                        viewModel.startCalibration(
                            previewBounds: CGRect(origin: .zero, size: previewSize),
                            imageSize: CGSize(width: 480, height: 640)
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)

                    Button("Dùng chế độ Chỉ đồng hồ") {
                        viewModel.cancel()
                        onSwitchToTimerOnly()
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                }
            }
            .padding()
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch viewModel.runState {
        case .idle:
            Text("Đặt điện thoại cố định nhìn thấy phần thân trên và mặt bạn khi ngồi lẫn cúi viết, sau đó nhấn Bắt đầu hiệu chỉnh.")
                .font(.body)
        case .running(let step, let secondsLeft):
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.headline)
                Text("\(step.instruction) Còn \(secondsLeft) giây.")
                    .font(.body)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        case .passed(let calibration):
            VStack(alignment: .leading, spacing: 8) {
                Label("Hiệu chỉnh đạt", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                if !viewModel.confusionSummary.isEmpty {
                    Text(viewModel.confusionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Tiếp tục chuẩn bị khóa") {
                    onCalibrationPassed(calibration)
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Chưa đạt điều kiện camera nghiêm", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.body)
                if !viewModel.confusionSummary.isEmpty {
                    Text(viewModel.confusionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
