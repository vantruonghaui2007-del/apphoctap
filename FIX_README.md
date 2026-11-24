# Bản sửa lỗi biên dịch MainActor — Tâm Học

Ngày: 24/11/2026. Chuẩn bị từ source hiện tại tại `T:\apphoctap` và log GitHub Actions bạn gửi (`Pasted text.txt`).

## Log mới thể hiện gì?

Lỗi chọn simulator cũ đã qua: Xcode nhận đúng UDID chữ hoa và bắt đầu biên dịch trên iPhone 16 Pro / iOS 18.5 simulator. Cảnh báo “Using the first of multiple matching destinations” không phải lỗi làm dừng lần này.

Lỗi chặn biên dịch:

```text
AppActivityMonitor.swift:13:58: error:
call to main actor-isolated static method 'readCurrentUIApplicationState()'
in a synchronous nonisolated context
```

Ở chế độ Swift 5 hiện tại, biểu thức đối số mặc định không được dùng để gọi hàm cần MainActor theo cách code đang viết. Lệnh test dừng trước khi XCTest chạy; exit code 65 là kết quả build thất bại.

## Các tệp đã chuẩn bị sửa

1. `TamHoc/Platform/AppActivityMonitor.swift`: đối số `initialState` mặc định là nil; đọc trạng thái UIApplication bên trong initializer có MainActor. Vẫn tôn trọng trạng thái được truyền từ test.
2. `TamHoc/Lock/GuidedAccessMonitor.swift`: đối số provider mặc định nil; tạo provider đọc UIKit trong initializer, khai báo kiểu hàm provider có MainActor. Xử lý cảnh báo actor isolation liên quan trong log, giữ logic phát notification không đổi.
3. `TamHocTests/CoordinatorTests.swift`: chuyển bốn đối số mặc định tạo đối tượng MainActor thành nil và tạo đối tượng bên trong hàm helper có MainActor. Đây là cùng mẫu lỗi đã tìm thấy khi rà source; log mới chưa đi đến bước biên dịch test target để xác nhận riêng bốn chỗ này.

Không đổi deployment target iOS 15.7, không bỏ test, không nới chế độ kiểm tra concurrency, không sửa luồng ký/cài app. Cảnh báo conformance `SessionRecord: Identifiable` trong HistoryView chưa được thay đổi vì không phải lỗi chặn build trong log.

## Cách áp dụng

Giải nén gói vào **`T:\apphoctap`**, đồng ý thay đúng ba tệp Swift ở các đường dẫn trên. Đừng giải nén thành `T:\apphoctap\TamHoc_Fix_Xcode_Actor\...`.

Gói còn có `actor-default-values.patch` để áp dụng chọn lọc bằng Git/IDE và `changed-files.json` chứa SHA-256 bản gốc/bản sửa. Nếu bạn đã chỉnh ba tệp này sau khi gửi log, hãy dùng patch thay vì ghi đè toàn bộ tệp.

Commit ba tệp đã thay và push lên GitHub để workflow tự chạy commit mới. Chỉ bấm Re-run trên run cũ sẽ tiếp tục dùng source của commit cũ.

## Kiểm chứng

- Đã đối chiếu trực tiếp chữ ký initializer, call site và log compiler thật từ GitHub.
- Bản gốc của ba tệp được giữ nguyên tại T:\apphoctap; phiên này không có quyền ghi vào đó. Gói này chưa tự áp dụng lên repo gốc và chưa được push.
- Đã tạo diff tối thiểu cùng hash để kiểm tra đúng phiên bản source.
- `git apply --check` thành công trên bản sao ba tệp gốc; đã áp dụng patch vào bản sao và đối chiếu nội dung với các tệp sửa trong gói.
- **Chưa chạy compiler/XCTest sau sửa** vì môi trường Windows hiện tại không có Swift/Xcode. Không khẳng định build đã thành công; cần kết quả GitHub Actions trên commit mới.

Nguồn ngôn ngữ: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0411-isolated-default-values.md (các quy tắc và giới hạn đối số mặc định theo actor).
