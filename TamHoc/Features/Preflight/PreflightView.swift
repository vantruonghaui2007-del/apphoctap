import SwiftUI
import UIKit
import StudyCore

public struct PreflightView: View {
    @ObservedObject var viewModel: PreflightViewModel
    let onNeedCalibration: () -> Void
    let onStartSession: (SessionConfiguration, Calibration?) async -> Void

    @State private var showingHelpSheet = false

    public init(
        viewModel: PreflightViewModel,
        onNeedCalibration: @escaping () -> Void,
        onStartSession: @escaping (SessionConfiguration, Calibration?) async -> Void
    ) {
        self.viewModel = viewModel
        self.onNeedCalibration = onNeedCalibration
        self.onStartSession = onStartSession
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Kiểm tra trước khi vào phiên")
                    .font(.title2.bold())

                checklistCard

                if viewModel.isCameraBlockedByPermissionOrHardware {
                    cameraFallbackCard
                } else if viewModel.presenceMode == .cameraVerified && viewModel.calibration == nil {
                    calibrationPromptCard
                }

                if !viewModel.isGuidedAccessEnabled {
                    guidedAccessGuideCard
                }

                if let error = viewModel.statusError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        viewModel.refreshChecks()
                        guard viewModel.canStartSession else { return }
                        viewModel.isStarting = true
                        defer { viewModel.isStarting = false }
                        do {
                            let cfg = try viewModel.makeConfiguration()
                            await onStartSession(cfg, viewModel.presenceMode == .cameraVerified ? viewModel.calibration : nil)
                        } catch {
                            viewModel.statusError = "Cấu hình phiên học không hợp lệ."
                        }
                    }
                } label: {
                    Text(viewModel.isStarting ? "Đang khởi tạo..." : "Bắt đầu phiên học")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTouchSize)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentTeal)
                .disabled(!viewModel.canStartSession)
                .accessibilityIdentifier("preflight.start")

                Button("Hướng dẫn bật & thoát Guided Access") {
                    showingHelpSheet = true
                }
                .font(.subheadline)
                .frame(minHeight: Theme.minTouchSize)
            }
            .padding()
        }
        .navigationTitle("Chuẩn bị khóa")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.refreshChecks()
        }
        .sheet(isPresented: $showingHelpSheet) {
            GuidedAccessInstructionsSheet()
        }
    }

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            checkRow(
                title: "Guided Access (iOS)",
                valueText: viewModel.isGuidedAccessEnabled ? "Đang bật" : "Chưa bật",
                icon: viewModel.isGuidedAccessEnabled ? "lock.fill" : "lock.open",
                tint: viewModel.isGuidedAccessEnabled ? Theme.accentTeal : .orange,
                identifier: "preflight.lockStatus"
            )

            Divider()

            if viewModel.presenceMode == .cameraVerified {
                let camOK = viewModel.isCameraReady
                checkRow(
                    title: "Camera & Hiệu chỉnh",
                    valueText: camOK ? "Sẵn sàng" : "Chưa sẵn sàng",
                    icon: camOK ? "checkmark.circle.fill" : "exclamationmark.circle",
                    tint: camOK ? Theme.accentTeal : .orange,
                    identifier: "preflight.cameraStatus"
                )
            } else {
                checkRow(
                    title: "Chế độ xác nhận",
                    valueText: "Chỉ đồng hồ (không camera)",
                    icon: "timer",
                    tint: .secondary,
                    identifier: "preflight.cameraStatus"
                )
            }

            Divider()

            checkRow(
                title: "Đường thoát hệ thống",
                valueText: "Nhấn nút sườn/Home 3 lần + mã",
                icon: "arrow.uturn.backward.circle",
                tint: .secondary,
                identifier: nil
            )
        }
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func checkRow(
        title: String,
        valueText: String,
        icon: String,
        tint: Color,
        identifier: String?
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(valueText)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .modifier(RowIDModifier(identifier: identifier))
            }
            Spacer()
        }
    }

    private var cameraFallbackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Không dùng được camera", systemImage: "video.slash.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Quyền camera bị từ chối/giới hạn hoặc máy không có camera trước. Bạn vẫn có thể học với chế độ Chỉ đồng hồ.")
                .font(.body)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Dùng chế độ Chỉ đồng hồ") {
                    viewModel.switchToTimerOnly()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentTeal)
                .frame(minHeight: Theme.minTouchSize)
                .accessibilityIdentifier("preflight.useTimerOnly")

                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Button("Mở Cài đặt") {
                        UIApplication.shared.open(settingsURL)
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: Theme.minTouchSize)
                }
            }
        }
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private var calibrationPromptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chưa có hiệu chỉnh vị trí")
                .font(.headline)
            Text("Cần kiểm tra ngồi thẳng, cúi viết và rời chỗ trước khi dùng camera.")
                .font(.body)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Hiệu chỉnh ngay", action: onNeedCalibration)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentTeal)
                    .frame(minHeight: Theme.minTouchSize)
                Button("Dùng Chỉ đồng hồ") {
                    viewModel.switchToTimerOnly()
                }
                .buttonStyle(.bordered)
                .frame(minHeight: Theme.minTouchSize)
            }
        }
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private var guidedAccessGuideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cần bật Guided Access trước khi bắt đầu")
                .font(.headline)
            Text("Nhấn nút sườn (hoặc nút Home) 3 lần để khóa máy vào Tâm Học. Nút Bắt đầu sẽ mở ngay khi iOS xác nhận Guided Access đang bật.")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("Kiểm tra lại trạng thái") {
                viewModel.refreshChecks()
            }
            .buttonStyle(.bordered)
            .frame(minHeight: Theme.minTouchSize)
        }
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

private struct RowIDModifier: ViewModifier {
    let identifier: String?
    func body(content: Content) -> some View {
        if let identifier = identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
