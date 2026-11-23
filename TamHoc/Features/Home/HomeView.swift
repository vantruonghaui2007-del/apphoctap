import SwiftUI
import StudyCore

public struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    let calibration: Calibration?
    let recoveredCount: Int
    let quarantinedCount: Int
    let settingsErrorMessage: String?
    let onContinueToSetup: () -> Void
    let onOpenHistory: () -> Void
    let onOpenSettings: () -> Void

    public init(
        viewModel: HomeViewModel,
        calibration: Calibration?,
        recoveredCount: Int,
        quarantinedCount: Int,
        settingsErrorMessage: String?,
        onContinueToSetup: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.calibration = calibration
        self.recoveredCount = recoveredCount
        self.quarantinedCount = quarantinedCount
        self.settingsErrorMessage = settingsErrorMessage
        self.onContinueToSetup = onContinueToSetup
        self.onOpenHistory = onOpenHistory
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                noticesSection

                durationSection

                modeSection

                Button(action: onContinueToSetup) {
                    Text(viewModel.cameraEnabled ? "Tiếp tục hiệu chỉnh & khóa" : "Chuẩn bị khóa phiên học")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTouchSize)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentTeal)
                .accessibilityIdentifier("home.continue")

                AdaptiveStack(spacing: 12) {
                    Button(action: onOpenHistory) {
                        Label("Lịch sử", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, minHeight: Theme.minTouchSize)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("home.history")

                    Button(action: onOpenSettings) {
                        Label("Cài đặt", systemImage: "gearshape")
                            .frame(maxWidth: .infinity, minHeight: Theme.minTouchSize)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("home.settings")
                }
            }
            .padding()
        }
        .navigationTitle("Tâm Học")
        .background(Theme.pageBackground)
    }

    @ViewBuilder
    private var noticesSection: some View {
        if recoveredCount > 0 {
            noticeBanner(
                icon: "exclamationmark.arrow.triangle.2.circlepath",
                text: "Có \(recoveredCount) phiên học trước bị gián đoạn khi đóng ứng dụng; đã lưu lại tới checkpoint cuối.",
                tint: .orange
            )
        }
        if quarantinedCount > 0 {
            noticeBanner(
                icon: "folder.badge.questionmark",
                text: "Đã chuyển \(quarantinedCount) tệp phiên học bị lỗi định dạng vào thư mục cách ly để không ảnh hưởng lịch sử.",
                tint: .blue
            )
        }
        if let settingsErrorMessage = settingsErrorMessage {
            noticeBanner(
                icon: "exclamationmark.triangle",
                text: settingsErrorMessage,
                tint: .orange
            )
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Thời lượng phiên học")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.selectedMinutes) phút")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(Theme.accentTeal)
                    .accessibilityIdentifier("home.duration")
            }

            HStack(spacing: 10) {
                ForEach(HomeViewModel.presetMinutes, id: \.self) { preset in
                    let isSelected = (viewModel.selectedMinutes == preset)
                    Button {
                        viewModel.selectedMinutes = preset
                    } label: {
                        Text("\(preset) ph")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: Theme.minTouchSize)
                    }
                    .buttonStyle(.bordered)
                    .tint(isSelected ? Theme.accentTeal : .secondary)
                    .background(isSelected ? Theme.accentTeal.opacity(0.14) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius))
                    .accessibilityLabel("Chọn \(preset) phút")
                }
            }

            Stepper(
                value: $viewModel.selectedMinutes,
                in: StudyCoreInfo.minPlannedMinutes...StudyCoreInfo.maxPlannedMinutes,
                step: 1
            ) {
                Text("Tùy chỉnh (2–180 phút)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: Theme.minTouchSize)

            Text("Không thể thay đổi thời lượng sau khi phiên học bắt đầu.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $viewModel.cameraEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Xác nhận hiện diện bằng camera")
                        .font(.headline)
                    Text(viewModel.cameraEnabled
                         ? "Kiểm tra có người tại bàn trên thiết bị. Nhắc khi vắng 30 giây."
                         : "Chỉ chạy đồng hồ và khóa Guided Access, không mở camera.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Theme.accentTeal)
            .frame(minHeight: Theme.minTouchSize)
            .accessibilityIdentifier("home.cameraToggle")

            if viewModel.cameraEnabled {
                HStack(spacing: 8) {
                    Image(systemName: calibration == nil ? "viewfinder.circle" : "checkmark.seal.fill")
                        .foregroundStyle(calibration == nil ? .secondary : Theme.accentTeal)
                        .accessibilityHidden(true)
                    Text(calibration == nil
                         ? "Cần hiệu chỉnh vị trí trước khi bắt đầu."
                         : "Đã có thông số hiệu chỉnh ROI (có thể hiệu chỉnh lại).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func noticeBanner(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius))
    }
}
