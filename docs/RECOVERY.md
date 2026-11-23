# Quy trình Khôi phục & Ranh giới An toàn — Tâm Học

## Nguyên tắc cốt lõi
1. **Bản mặc định dùng Guided Access thủ công của iOS:** người dùng tự bật và tự thoát bằng cơ chế hệ thống (nhấn nút sườn/Home 3 lần + nhập mã Guided Access đã đặt trong Cài đặt iOS).
2. **Không tự mở khóa:** ứng dụng **không** thể tự tắt Guided Access thủ công khi hết giờ, khi crash, khi hết pin hoặc khi người dùng bấm kết thúc sớm. Giao diện luôn nói rõ ranh giới này.
3. **Không xóa dữ liệu & không MDM ẩn:** ứng dụng không tự reset máy, không enroll MDM, không dùng private API hoặc ngăn tắt nguồn thiết bị.

## Các tình huống khôi phục & lỗi lưu trữ
| Tình huống | Hành vi đã triển khai trong mã nguồn | Đường thoát cho người dùng | Trạng thái trên máy thật |
|---|---|---|---|
| Bật Guided Access trước khi xong preflight | App giữ nguyên nút đóng/quay lại và hướng dẫn thoát; không tự bắt đầu phiên | Thoát Guided Access bằng nút sườn/Home 3 lần + mã | **UNVERIFIED (chưa có máy thật)** |
| Hết giờ phiên học bình thường | App chuyển `CompletionView`, giữ nguyên nhắc thoát Guided Access | Nhấn nút sườn/Home 3 lần + nhập mã để thoát | **UNVERIFIED (chưa có máy thật)** |
| Thoát Guided Access giữa phiên | `GuidedAccessMonitor` đọc `isEnabled == false` -> `endedEarly(.lockReleased)`, dừng camera & lưu | Người dùng đã ở ngoài Guided Access | **UNVERIFIED (chưa có máy thật)** |
| Kill app / Crash / Reboot giữa phiên | Lần mở sau `recoverUnfinishedSessions()` chuyển `running` -> `interrupted(.processRestart)` tại checkpoint cuối (mất tối đa 5 giây gần nhất), không cộng bù thời gian | Nếu iOS còn kẹt trong Guided Access: nhấn 3 lần + mã; sau reboot thường Guided Access đã thoát | **UNVERIFIED (chưa có máy thật)** |
| Lưu dữ liệu ban đầu thất bại / Disk full | `start()` từ chối bắt đầu phiên và giải phóng camera; **không** tự xóa lịch sử cũ | Giải phóng dung lượng trên iPhone thủ công hoặc xuất/xóa lịch sử trong Cài đặt | Unit test viết xong; **NOT RUN (requires macOS)** |
| Lưu giữa phiên thất bại | Kết thúc sớm với `.endedEarly(.storageFailure)` và hiện cảnh báo kết quả có thể chưa lưu | Không khóa kẹt; thoát Guided Access bình thường | Unit test viết xong; **NOT RUN (requires macOS)** |
| Tệp JSON hỏng / Schema mới hơn (ví dụ v99) | Tệp hỏng được dời sang `Sessions/Quarantine/` không làm mất các phiên tốt; schema mới được giữ nguyên chỉ đọc | Dữ liệu tốt vẫn hiển thị bình thường | Unit test viết xong; **NOT RUN (requires macOS)** |
| Thiết bị quá nóng (`thermalState == .critical`) | Dừng ngay pipeline camera, kết thúc sớm `.thermalLimit`, khôi phục `isIdleTimerDisabled` | Thoát Guided Access và để máy nguội | Unit test viết xong; **Device: UNVERIFIED** |
| Thu hồi quyền camera giữa chừng / Không có mạng | App hoạt động 100% ngoại tuyến; nếu camera bị thu hồi khi quay lại foreground, chuyển `unknown(.cameraUnavailable)` và vẫn cho kết thúc bình thường | Người dùng tự chọn kết thúc hoặc dùng Chỉ đồng hồ ở phiên sau | Unit test viết xong; **Device: UNVERIFIED** |
| Quên mã Guided Access | App không lưu, không đọc và không thay đổi mã Guided Access | Giữ phím nguồn + âm lượng theo hướng dẫn tắt/khởi động lại cưỡng bức của Apple | Tham khảo tài liệu Apple [S2] |
