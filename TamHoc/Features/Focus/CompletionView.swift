import SwiftUI
import StudyCore

public struct CompletionView: View {
    let record: SessionRecord
    let isGuidedAccessEnabled: Bool
    let isFinalizing: Bool
    let persistenceWarning: String?
    let onDone: () -> Void

    @State private var showingHelpSheet = false

    public init(
        record: SessionRecord,
        isGuidedAccessEnabled: Bool,
        isFinalizing: Bool = false,
        persistenceWarning: String?,
        onDone: @escaping () -> Void
    ) {
        self.record = record
        self.isGuidedAccessEnabled = isGuidedAccessEnabled
        self.isFinalizing = isFinalizing
        self.persistenceWarning = persistenceWarning
        self.onDone = onDone
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(PresenceDisplayFormatter.statusTitle(for: record.status))
                        .font(.title.bold())
                        .accessibilityIdentifier("summary.status")
                    Text("Thời lượng thực tế: \(DurationFormatter.detailedDuration(record.elapsedSeconds)) / \(DurationFormatter.detailedDuration(record.configuration.plannedSeconds))")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                guidedAccessExitCard

                if let warning = persistenceWarning {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(warning)
                            .font(.footnote)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius))
                }

                breakdownCard

                if isFinalizing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Đang lưu kết quả và giải phóng tài nguyên phiên học...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: onDone) {
                    Text(isFinalizing ? "Đang hoàn tất phiên..." : "Về màn hình chính")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTouchSize)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentTeal)
                .disabled(isFinalizing)
                .accessibilityIdentifier("summary.done")
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .sheet(isPresented: $showingHelpSheet) {
            GuidedAccessInstructionsSheet()
        }
    }

    private var guidedAccessExitCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                isGuidedAccessEnabled
                    ? "Guided Access vẫn đang bật"
                    : "Guided Access đã tắt",
                systemImage: isGuidedAccessEnabled ? "lock.fill" : "lock.open"
            )
            .font(.headline)
            .foregroundStyle(isGuidedAccessEnabled ? .orange : Theme.accentTeal)

            Text(
                isGuidedAccessEnabled
                    ? "Ứng dụng đã kết thúc đồng hồ nhưng không thể tự thoát khóa hệ thống. Để mở khóa máy, nhấn nút sườn (hoặc nút Home) 3 lần và nhập mã Guided Access."
                    : "Bạn đã thoát chế độ Guided Access. Dữ liệu phiên học được lưu nội bộ trên thiết bị."
            )
            .font(.body)
            .foregroundStyle(.secondary)

            Button("Xem hướng dẫn thoát Guided Access") {
                showingHelpSheet = true
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: Theme.minTouchSize)
            .accessibilityIdentifier("summary.guidedAccessHelp")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private var breakdownCard: some View {
        let buckets = record.secondsByBucket
        return VStack(alignment: .leading, spacing: 12) {
            Text("Phân bổ thời gian")
                .font(.headline)

            if record.configuration.presenceMode == .timerOnly {
                Text("Chế độ Chỉ đồng hồ: không xác minh hiện diện bằng camera.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("summary.unverifiedNotice")
                metricRow("Không dùng camera", seconds: buckets[.unverified] ?? 0, tint: Theme.accentTeal)
                metricRow("Ngoài ứng dụng", seconds: buckets[.ineligible] ?? 0, tint: .secondary)
            } else {
                metricRow("Có mặt (đã xác nhận)", seconds: buckets[.present] ?? 0, tint: Theme.accentTeal)
                metricRow("Vắng mặt", seconds: buckets[.absent] ?? 0, tint: .orange)
                metricRow("Không thể xác nhận", seconds: buckets[.unknown] ?? 0, tint: .secondary)
                metricRow("Ngoài ứng dụng", seconds: buckets[.ineligible] ?? 0, tint: .secondary)
            }

            if case .interrupted = record.status {
                Text("Số liệu ghi nhận tới checkpoint gần nhất (có thể chênh tối đa 5 giây trước khi đóng đột ngột).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func metricRow(_ label: String, seconds: Double, tint: Color) -> some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            Text(DurationFormatter.detailedDuration(seconds))
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}
