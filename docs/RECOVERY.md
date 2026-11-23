# Quy trình Khôi phục & Ranh giới An toàn — Tâm Học

## Nguyên tắc cốt lõi
1. **Bản mặc định dùng Guided Access thủ công của iOS:** người dùng tự bật và tự thoát bằng cơ chế hệ thống (nhấn nút sườn/Home 3 lần + nhập mã Guided Access đã đặt trong Cài đặt iOS).
2. **Không tự mở khóa:** ứng dụng **không** thể tự tắt Guided Access thủ công khi hết giờ, khi crash hoặc khi người dùng bấm kết thúc sớm. Giao diện luôn nói rõ ranh giới này.
3. **Không xóa dữ liệu & không MDM ẩn:** ứng dụng không tự reset máy, không enroll MDM, không dùng private API hoặc ngăn tắt nguồn thiết bị.

## Các tình huống khôi phục (bảng thiết kế & trạng thái kiểm chứng)
| Tình huống | Hành vi ứng dụng | Đường thoát cho người dùng | Trạng thái trên máy thật |
|---|---|---|---|
| Vào Guided Access trước khi xong preflight | App vẫn hiện nút quay lại/hướng dẫn, không tự chạy đồng hồ | Thoát Guided Access bằng nút sườn/Home 3 lần + mã | **UNVERIFIED (chưa có máy thật)** |
| Hết giờ phiên học bình thường | App chuyển màn hình tổng kết, giữ nguyên nhắc thoát Guided Access | Nhấn nút sườn/Home 3 lần + nhập mã để thoát | **UNVERIFIED (chưa có máy thật)** |
| Người dùng thoát Guided Access giữa phiên | `GuidedAccessMonitor` đọc `isEnabled == false`, kết thúc sớm với `lockReleased`, lưu checkpoint cuối | Người dùng đã ở ngoài Guided Access | **UNVERIFIED (chưa có máy thật)** |
| App crash / bị kill / thiết bị reboot giữa phiên | Lần mở sau phát hiện bản ghi `running`, chuyển thành `interrupted(processRestart)` tại checkpoint cuối (mất tối đa ~5 giây gần nhất), không cộng bù thời gian | Nếu iOS vẫn đang ở Guided Access sau crash: dùng nút sườn/Home 3 lần + mã; nếu reboot thường Guided Access đã tự thoát | **UNVERIFIED (chưa có máy thật)** |
| Quên mã Guided Access | App không lưu/thu thập/đổi mã Guided Access của iOS | Giữ nút nguồn tắt/khởi động lại cưỡng bức theo hỗ trợ Apple hoặc khôi phục qua Finder/iTunes theo hướng dẫn Apple | Tham khảo tài liệu Apple [S2] |

## Ghi chú Task 1
- Chưa thử nghiệm được trên iPhone thật do không có thiết bị và macOS/Xcode tại môi trường hiện tại; giữ cổng phát hành ở trạng thái **UNVERIFIED**.
