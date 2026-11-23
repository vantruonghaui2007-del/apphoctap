# Biên bản Kiểm chứng Thiết bị Thật — Tâm Học

**Trạng thái tổng quan:** **NOT RUN / UNVERIFIED** (thiếu macOS/Xcode và thiết bị iPhone thật tại môi trường phát triển Windows).
Chứng cứ giả lập/unit test chỉ xác nhận logic ở mức mã nguồn; **không** thay thế chứng cứ máy thật cho khóa Guided Access, độ chính xác camera, nhiệt và ký cài IPA.

## 1. Ma trận Thiết bị & Hệ điều hành
| Thiết bị / Simulator | iOS Version | Vai trò | Commit | Kết quả Unit/UI | Kết quả Thiết bị Thật | Ghi chú |
|---|---|---|---|---|---|---|
| iPhone thật (iOS 15.7.x) | 15.7.x | Tối thiểu bắt buộc | `HEAD` | NOT RUN | NOT RUN | Release gate: cần máy thật 15.7.x |
| iPhone thật (iOS mới hơn) | 16/17/18+ | Hiện đại / notch / Dynamic Island | `HEAD` | NOT RUN | NOT RUN | Cần thử trên máy thật |
| iPhone SE / màn nhỏ (Simulator) | 15.7 / mới hơn | Layout & Dynamic Type XXXL | `HEAD` | NOT RUN | N/A | Chạy qua `./scripts/verify.sh` trên macOS |
| iPhone Pro Max / màn lớn (Simulator) | Mới hơn | Layout & VoiceOver | `HEAD` | NOT RUN | N/A | Chạy qua `./scripts/verify.sh` trên macOS |

## 2. Ma trận Guided Access & Vòng đời
| Kịch bản | Mục tiêu kiểm tra | Loại bằng chứng | Kết quả |
|---|---|---|---|
| Bật Guided Access bình thường | `preflight.lockStatus` đổi `Đang bật`, nút `Bắt đầu` mở | Thiết bị thật | NOT RUN |
| Nhập sai mã khi thoát Guided Access | iOS xử lý tại hệ thống; app không can thiệp/giữ khóa | Thiết bị thật | NOT RUN |
| Hết giờ phiên học trong app | App hiện màn tổng kết và nhắc thoát Guided Access thủ công | Thiết bị thật | NOT RUN |
| Thoát Guided Access giữa phiên | `lockReleased` kết thúc sớm, dừng camera, lưu checkpoint | Thiết bị thật + Unit mock | Unit: NOT RUN (requires macOS) / Device: NOT RUN |
| Kill app / Crash / Reboot giữa phiên | Mở lại chuyển `interrupted(processRestart)` tại checkpoint cuối | Thiết bị thật + Unit | Unit: NOT RUN (requires macOS) / Device: NOT RUN |

## 3. Ma trận Camera, Độ chính xác & Hiệu năng
| Kịch bản | Ngưỡng mục tiêu | Loại bằng chứng | Kết quả |
|---|---|---|---|
| Từ chối / thu hồi quyền camera | Không chạy capture, cung cấp `Chỉ đồng hồ` ngay | Unit + Thiết bị thật | NOT RUN |
| Thiếu sáng (<0.08 luma) & che ống kính | Trả `unknown(.lowLight)` / `absent`, không cộng `present` | Unit (`CVPixelBuffer`) + Thiết bị thật | NOT RUN |
| Cúi viết / ngồi thẳng / người đi qua / rời chỗ | Hiệu chỉnh 3 bước đạt và confusion counts thực tế | Thiết bị thật | NOT RUN |
| 20 lần rời bàn > 60 giây | Phát hiện >= 19/20 trong <= 3s sau ngưỡng | Thiết bị thật | NOT RUN |
| 2 giờ học giấy thực tế | <= 1 cảnh báo giả (false alarm) | Thiết bị thật | NOT RUN |
| Phiên 50 phút (máy cũ & mới) | Peak memory < 150MB (Instruments), pin & nhiệt ổn định | Instruments + Thiết bị thật | NOT RUN |
| Thermal `.serious` (1 Hz) & `.critical` (`thermalLimit`) | Giảm tần suất 1 Hz; critical dừng capture & kết thúc sớm | Injected thermal event + Unit | NOT RUN (requires macOS) |

## 4. Hướng dẫn điền biên bản khi chạy trên macOS + iPhone thật
1. Ghi rõ model máy (ví dụ iPhone 8 / iPhone 13 / iPhone 15), phiên bản iOS cụ thể, phiên bản Xcode/SDK và commit hash.
2. Ghi rõ thao tác bật/thoát Guided Access thực tế quan sát được trên đúng phiên bản iOS đó (không chép mù tài liệu đời iOS khác).
3. Với bài thử nhiệt `.critical`: sử dụng injected event trong test/Instruments nếu không thể tạo ngưỡng nhiệt an toàn ngoài thực tế, và ghi rõ loại bằng chứng là `injected`.
4. Nếu chưa đạt 19/20 lần rời bàn hoặc <= 1 cảnh báo giả trong 2 giờ học giấy, đánh dấu camera là `experimental` và giữ release gate.
