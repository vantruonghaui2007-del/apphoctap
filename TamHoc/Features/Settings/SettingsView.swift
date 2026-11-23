import SwiftUI
import StudyCore

public struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let onRecalibrate: () -> Void
    let onClearHistory: () async -> Void

    @State private var showingGuides = false
    @State private var showingDeleteConfirm = false

    public init(
        viewModel: SettingsViewModel,
        onRecalibrate: @escaping () -> Void,
        onClearHistory: @escaping () async -> Void
    ) {
        self.viewModel = viewModel
        self.onRecalibrate = onRecalibrate
        self.onClearHistory = onClearHistory
    }

    public var body: some View {
        Form {
            Section("Mặc định cho phiên mới") {
                Stepper(
                    "Thời lượng mặc định: \(viewModel.defaultMinutes) phút",
                    value: $viewModel.defaultMinutes,
                    in: StudyCoreInfo.minPlannedMinutes...StudyCoreInfo.maxPlannedMinutes
                )
                .onValueChange(of: viewModel.defaultMinutes) { _ in
                    Task { await viewModel.persist() }
                }

                Toggle("Bật xác nhận camera mặc định", isOn: $viewModel.defaultCameraEnabled)
                    .tint(Theme.accentTeal)
                    .onValueChange(of: viewModel.defaultCameraEnabled) { _ in
                        Task { await viewModel.persist() }
                    }

                Toggle("Nhắc khi vắng 30 giây", isOn: $viewModel.warningsEnabled)
                    .tint(Theme.accentTeal)
                    .onValueChange(of: viewModel.warningsEnabled) { _ in
                        Task { await viewModel.persist() }
                    }
            }

            Section("Camera & Hướng dẫn khôi phục") {
                Button("Hiệu chỉnh lại camera") {
                    onRecalibrate()
                }
                .frame(minHeight: Theme.minTouchSize)

                Button("Hướng dẫn bật & thoát Guided Access") {
                    showingGuides = true
                }
                .frame(minHeight: Theme.minTouchSize)
            }

            Section("Dữ liệu trên thiết bị") {
                Button("Xóa toàn bộ lịch sử phiên học", role: .destructive) {
                    showingDeleteConfirm = true
                }
                .frame(minHeight: Theme.minTouchSize)
            }

            if let err = viewModel.saveErrorMessage {
                Section {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Cài đặt")
        .sheet(isPresented: $showingGuides) {
            GuidedAccessInstructionsSheet()
        }
        .confirmationDialog(
            "Xóa toàn bộ lịch sử?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Xóa tất cả", role: .destructive) {
                Task { await onClearHistory() }
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Thao tác này xóa vĩnh viễn các phiên học đã lưu trên máy.")
        }
    }
}
