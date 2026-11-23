import SwiftUI
import StudyCore

public struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let spacing: CGFloat
    private let content: () -> Content

    public init(spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
        } else {
            HStack(spacing: spacing) {
                content()
            }
        }
    }
}

public struct AppNavigationContainer<Content: View>: View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        #if compiler(>=5.7)
        if #available(iOS 16.0, *) {
            NavigationStack {
                content()
            }
        } else {
            NavigationView {
                content()
            }
            .navigationViewStyle(.stack)
        }
        #else
        NavigationView {
            content()
        }
        .navigationViewStyle(.stack)
        #endif
    }
}

public extension View {
    @ViewBuilder
    func onValueChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        #if compiler(>=5.9)
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value, perform: action)
        }
        #else
        self.onChange(of: value, perform: action)
        #endif
    }
}

public struct StatusPill: View {
    public let title: String
    public let systemImage: String
    public let tint: Color
    public let identifier: String?

    public init(title: String, systemImage: String, tint: Color, identifier: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.identifier = identifier
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: Theme.minTouchSize)
        .background(tint.opacity(0.14))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .modifier(OptionalIdentifierModifier(identifier: identifier))
    }
}

private struct OptionalIdentifierModifier: ViewModifier {
    let identifier: String?
    func body(content: Content) -> some View {
        if let identifier = identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

public struct ProgressRingView: View {
    public let progress: Double
    public let lineWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(progress: Double, lineWidth: CGFloat = 12) {
        self.progress = min(1, max(0, progress))
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.accentTeal.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Theme.accentTeal,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: progress)
        }
        .accessibilityHidden(true)
    }
}

public enum DurationFormatter {
    public static func mmss(_ seconds: Double) -> String {
        let clamped = max(0, Int(seconds.rounded(.down)))
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    public static func minutesLabel(_ seconds: Double) -> String {
        let mins = Int((seconds / 60.0).rounded())
        return "\(mins) phút"
    }

    public static func detailedDuration(_ seconds: Double) -> String {
        let clamped = max(0, Int(seconds.rounded()))
        let mins = clamped / 60
        let secs = clamped % 60
        if mins == 0 {
            return "\(secs) giây"
        }
        if secs == 0 {
            return "\(mins) phút"
        }
        return "\(mins) phút \(secs) giây"
    }
}

public enum PresenceDisplayFormatter {
    public static func textAndIcon(
        for presence: PresenceValue,
        mode: PresenceMode
    ) -> (text: String, icon: String, tint: Color) {
        if mode == .timerOnly {
            return ("Không dùng camera", "timer", .secondary)
        }
        switch presence {
        case .present:
            return ("Có mặt", "checkmark.circle.fill", Theme.accentTeal)
        case .absent:
            return ("Không thấy ở vị trí", "person.crop.circle.badge.exclamationmark", .orange)
        case .unknown(let issue):
            switch issue {
            case .warmingUp:
                return ("Đang chờ ổn định", "hourglass", .blue)
            case .lowLight, .stale, .cameraUnavailable, .thermal, .detectorFailure:
                return ("Không thể xác nhận", "exclamationmark.triangle.fill", .orange)
            }
        }
    }

    public static func statusTitle(for status: SessionStatus) -> String {
        switch status {
        case .running:
            return "Đang học"
        case .completed:
            return "Hoàn thành phiên học"
        case .endedEarly(let reason):
            switch reason {
            case .deadline:
                return "Hoàn thành phiên học"
            case .userEnded:
                return "Kết thúc sớm theo yêu cầu"
            case .lockReleased:
                return "Kết thúc sớm (đã thoát Guided Access)"
            case .processRestart:
                return "Phiên bị gián đoạn khi đóng ứng dụng"
            case .storageFailure:
                return "Kết thúc sớm do lỗi lưu dữ liệu"
            case .thermalLimit:
                return "Kết thúc sớm do thiết bị quá nóng"
            case .clockFailure:
                return "Kết thúc sớm do lỗi đồng hồ hệ thống"
            }
        case .interrupted:
            return "Phiên bị gián đoạn (tới checkpoint cuối)"
        }
    }
}

public struct GuidedAccessInstructionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        AppNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Cách bật và thoát Guided Access")
                        .font(.title2.bold())

                    instructionCard(
                        title: "1. Bật trong Cài đặt iOS (chỉ làm một lần)",
                        body: "Mở Cài đặt > Trợ năng (Accessibility) > Truy cập được hướng dẫn (Guided Access) và bật công tắc. Đặt mật mã riêng hoặc Face ID/Touch ID để thoát."
                    )

                    instructionCard(
                        title: "2. Bật trước khi bấm Bắt đầu",
                        body: "Khi đang ở màn hình Chuẩn bị khóa của Tâm Học, nhấn nút sườn (hoặc nút Home trên máy cũ) 3 lần liên tiếp để bật Guided Access."
                    )

                    instructionCard(
                        title: "3. Thoát khi kết thúc hoặc khi cần dừng",
                        body: "Nhấn nút sườn (hoặc nút Home) 3 lần, nhập mã Guided Access của bạn rồi chọn Kết thúc (End) ở góc trên màn hình. Tâm Học không thể tự tắt Guided Access thay bạn."
                    )
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                        .frame(minHeight: Theme.minTouchSize)
                }
            }
        }
    }

    private func instructionCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius))
    }
}
