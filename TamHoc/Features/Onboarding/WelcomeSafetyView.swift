import SwiftUI

public struct WelcomeSafetyView: View {
    let onAcknowledge: () -> Void

    public init(onAcknowledge: @escaping () -> Void) {
        self.onAcknowledge = onAcknowledge
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "graduationcap.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.accentTeal)
                        .accessibilityHidden(true)
                    Text("Chào mừng đến với Tâm Học")
                        .font(.largeTitle.bold())
                    Text("Giữ nhịp tập trung ngoại tuyến, tôn trọng quyền kiểm soát thiết bị của bạn.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                safetyCard(
                    icon: "lock.shield",
                    title: "Giới hạn của chế độ khóa",
                    description: "Tâm Học dựa vào tính năng Guided Access (Truy cập được hướng dẫn) có sẵn của iOS. Nếu biết mật mã hệ thống, bạn luôn có thể thoát. Ứng dụng không tự gỡ khóa khi hết giờ."
                )

                safetyCard(
                    icon: "camera.viewfinder",
                    title: "Quyền riêng tư camera",
                    description: "Chế độ xác nhận hiện diện hoàn toàn tùy chọn. Mọi khung hình chỉ được phân tích trực tiếp trên máy để biết có người tại bàn, không lưu ảnh/video, không nhận diện danh tính và không gửi ra ngoài."
                )

                safetyCard(
                    icon: "arrow.uturn.backward.circle",
                    title: "Cách thoát khỏi Guided Access",
                    description: "Trước khi bật khóa, hãy chắc chắn bạn nhớ mật mã Guided Access đã cài trong iOS. Để thoát bất cứ lúc nào: nhấn nút sườn (hoặc nút Home) 3 lần và nhập mã."
                )

                Button(action: onAcknowledge) {
                    Text("Tôi đã hiểu và tiếp tục")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTouchSize)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentTeal)
                .accessibilityIdentifier("welcome.continue")
            }
            .padding()
        }
        .background(Theme.pageBackground)
    }

    private func safetyCard(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.accentTeal)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
