import SwiftUI
import UIKit
import StudyCore

public struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @State private var activeSheet: HistorySheet?

    public init(viewModel: HistoryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if viewModel.unsupportedSchemaCount > 0 {
                Text("Có \(viewModel.unsupportedSchemaCount) tệp phiên học định dạng mới hơn được giữ nguyên ở chế độ chỉ đọc.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if viewModel.records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chưa có phiên học nào")
                        .font(.headline)
                    Text("Các phiên học đã hoàn thành hoặc dừng sớm sẽ được lưu nội bộ tại đây.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            } else {
                ForEach(viewModel.records, id: \.id) { record in
                    Button {
                        activeSheet = .detail(record)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(PresenceDisplayFormatter.statusTitle(for: record.status))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(formattedDate(record.startedWallDate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(DurationFormatter.detailedDuration(record.elapsedSeconds))
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(Theme.accentTeal)
                                Text(record.configuration.presenceMode == .cameraVerified ? "Có camera" : "Chỉ đồng hồ")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: Theme.minTouchSize)
                    }
                    .swipeActions {
                        Button("Xóa", role: .destructive) {
                            Task { await viewModel.delete(id: record.id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Lịch sử")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !viewModel.records.isEmpty {
                    Menu {
                        Button("Xuất CSV") {
                            viewModel.prepareCSVExport()
                        }
                        Button("Xuất JSON") {
                            viewModel.prepareJSONExport()
                        }
                    } label: {
                        Label("Xuất", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Xuất lịch sử học")
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .onValueChange(of: viewModel.exportFileURL) { url in
            if let url = url {
                activeSheet = .export(url)
            }
        }
        .sheet(item: $activeSheet, onDismiss: {
            viewModel.exportFileURL = nil
        }) { sheet in
            switch sheet {
            case .detail(let record):
                AppNavigationContainer {
                    SessionDetailView(record: record)
                }
            case .export(let url):
                ShareSheetRepresentable(activityItems: [url])
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "vi_VN")
        return formatter.string(from: date)
    }
}

private enum HistorySheet: Identifiable {
    case detail(SessionRecord)
    case export(URL)

    var id: String {
        switch self {
        case .detail(let record):
            return "detail-\(record.id.uuidString)"
        case .export(let url):
            return "export-\(url.absoluteString)"
        }
    }
}

public struct ShareSheetRepresentable: UIViewControllerRepresentable {
    public let activityItems: [Any]

    public init(activityItems: [Any]) {
        self.activityItems = activityItems
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension SessionRecord: Identifiable {}

private struct SessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let record: SessionRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(PresenceDisplayFormatter.statusTitle(for: record.status))
                    .font(.title2.bold())
                Text("Đã học: \(DurationFormatter.detailedDuration(record.elapsedSeconds)) / \(DurationFormatter.detailedDuration(record.configuration.plannedSeconds))")
                    .font(.body)
                    .foregroundStyle(.secondary)

                let buckets = record.secondsByBucket
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tổng hợp thời gian")
                        .font(.headline)
                    if record.configuration.presenceMode == .timerOnly {
                        detailRow("Không dùng camera", buckets[.unverified] ?? 0)
                    } else {
                        detailRow("Có mặt", buckets[.present] ?? 0)
                        detailRow("Vắng mặt", buckets[.absent] ?? 0)
                        detailRow("Không thể xác nhận", buckets[.unknown] ?? 0)
                    }
                    detailRow("Ngoài ứng dụng", buckets[.ineligible] ?? 0)
                }
                .padding()
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sự kiện đã ghi (\(record.events.count))")
                        .font(.headline)
                    if record.events.isEmpty {
                        Text("Các sự kiện chi tiết quá 30 ngày đã được dọn gọn theo chính sách lưu trữ.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(record.events, id: \.id) { event in
                            HStack {
                                Text(DurationFormatter.mmss(event.elapsedSeconds))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(event.kind.rawValue)
                                    .font(.subheadline)
                                if let detail = event.detail {
                                    Text("(\(detail.rawValue))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .padding()
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            .padding()
        }
        .navigationTitle("Chi tiết phiên")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Đóng") { dismiss() }
            }
        }
    }

    private func detailRow(_ label: String, _ seconds: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(DurationFormatter.detailedDuration(seconds))
                .monospacedDigit()
                .fontWeight(.semibold)
        }
    }
}
