import SwiftUI
import StudyCore

public struct FocusView: View {
    @ObservedObject var sessionViewModel: SessionViewModel
    @State private var showingEndConfirmation = false
    @State private var showingHelpSheet = false

    @ScaledMetric(relativeTo: .largeTitle) private var ringDiameter: CGFloat = 220
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(sessionViewModel: SessionViewModel) {
        self.sessionViewModel = sessionViewModel
    }

    private var snapshot: SessionSnapshot? {
        sessionViewModel.snapshot
    }

    private var mode: PresenceMode {
        sessionViewModel.activeConfiguration?.presenceMode ?? .timerOnly
    }

    private var plannedSeconds: Double {
        sessionViewModel.activeConfiguration?.plannedSeconds ?? 3000
    }

    private var progress: Double {
        guard plannedSeconds > 0 else { return 0 }
        return min(1, max(0, (snapshot?.elapsedSeconds ?? 0) / plannedSeconds))
    }

    private var remainingText: String {
        DurationFormatter.mmss(snapshot?.remainingSeconds ?? plannedSeconds)
    }

    private var presenceInfo: (text: String, icon: String, tint: Color) {
        PresenceDisplayFormatter.textAndIcon(
            for: snapshot?.presence ?? .unknown(.warmingUp),
            mode: mode
        )
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AdaptiveStack(spacing: 12) {
                    StatusPill(
                        title: sessionViewModel.isGuidedAccessEnabled ? "Guided Access đang bật" : "Guided Access đã tắt",
                        systemImage: sessionViewModel.isGuidedAccessEnabled ? "lock.fill" : "lock.open",
                        tint: sessionViewModel.isGuidedAccessEnabled ? Theme.accentTeal : .orange,
                        identifier: "focus.lockStatus"
                    )
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer()
                    }
                    Button {
                        showingHelpSheet = true
                    } label: {
                        Label("Trợ giúp", systemImage: "questionmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(minWidth: Theme.minTouchSize, minHeight: Theme.minTouchSize)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("focus.help")
                    .accessibilityLabel("Hướng dẫn thoát Guided Access")
                }

                ZStack {
                    ProgressRingView(progress: progress, lineWidth: 14)
                        .frame(width: min(ringDiameter, 280), height: min(ringDiameter, 280))

                    VStack(spacing: 6) {
                        Text("Còn lại")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(remainingText)
                            .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.45)
                            .accessibilityIdentifier("focus.remaining")
                            .accessibilityLabel("Thời gian còn lại \(remainingText)")
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 8)

                StatusPill(
                    title: presenceInfo.text,
                    systemImage: presenceInfo.icon,
                    tint: presenceInfo.tint,
                    identifier: "focus.presence"
                )

                if mode == .cameraVerified {
                    Text("Camera chỉ phân tích tại máy để xác nhận hiện diện, không lưu ảnh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Đang học ở chế độ Chỉ đồng hồ (không xác minh hiện diện qua camera).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let warning = sessionViewModel.persistenceWarningMessage {
                    Text(warning)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                Button(role: .destructive) {
                    showingEndConfirmation = true
                } label: {
                    Text("Kết thúc phiên sớm")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTouchSize)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("focus.endEarly")
            }
            .padding()
        }
        .background(Theme.pageBackground)
        .confirmationDialog(
            "Kết thúc phiên học?",
            isPresented: $showingEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("Dừng phiên học", role: .destructive) {
                Task {
                    await sessionViewModel.endEarly()
                }
            }
            Button("Tiếp tục học", role: .cancel) {}
        } message: {
            Text("Dừng phiên sẽ kết thúc đồng hồ của Tâm Học, nhưng Guided Access của iOS có thể vẫn đang bật — bạn cần tự thoát Guided Access bằng thao tác hệ thống.")
        }
        .sheet(isPresented: $showingHelpSheet) {
            GuidedAccessInstructionsSheet()
        }
    }
}
