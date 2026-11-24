# Build Tâm Học trên GitHub bằng máy Windows

## Cài workflow vào dự án

Chép `.github/workflows/ios-build.yml` và tài liệu này vào đúng đường dẫn tương ứng trong thư mục `T:\apphoctap`. Workflow phải nằm ở thư mục gốc repository, cùng cấp với `TamHoc.xcodeproj`, không lồng thêm thư mục `TamHoc_GitHub_Build`.

Gói này chỉ thêm workflow và tài liệu, không thay mã Swift hiện tại. Git phải theo dõi tệp `.github/workflows/ios-build.yml`; đừng chỉ upload các thư mục source và bỏ sót `.github`.

## Chạy lần đầu

1. Tạo repository GitHub và đưa mã nguồn hiện tại cùng workflow lên đó. Repository riêng tư dùng hạn mức Actions của tài khoản; kiểm tra Billing trước khi bật tính phí vượt mức.
2. Mỗi lần push code lên bất kỳ nhánh nào, workflow **Build iOS IPA** tự chạy. Có thể chạy lại bằng **Actions → Build iOS IPA → Run workflow** sau khi workflow có trên nhánh mặc định.
3. Workflow chọn macOS 15 / Xcode 16.4, chạy StudyCore tests và unit/UI tests trên một iPhone simulator có sẵn, sau đó build Release cho thiết bị thật với target iOS 15.7.
4. Chỉ khi các bước trên thành công, workflow mới đóng gói IPA. Nếu đỏ, mở bước bị lỗi và tải artifact `TamHoc-diagnostics-*` để xem log/XCTest result; chưa có IPA ở lần chạy đó là đúng.
5. Khi xanh, vào cuối trang lần chạy, tải artifact **TamHoc-unsigned**. Giải nén ZIP của GitHub để lấy **TamHoc-unsigned.ipa** bên trong. Hai tệp đi kèm ghi SHA-256 và thông tin bản build.

## Ký và cài bằng 3uTools

IPA này được đóng gói đúng cấu trúc `Payload/TamHoc.app`, nhưng **chưa ký**. Nó là đầu vào để ký lại, không phải bản có thể cài trực tiếp ngay lập tức. Không đổi đuôi một ZIP source thành IPA.

1. Kết nối iPhone vào Windows, mở 3uTools và tin cậy máy tính trên iPhone.
2. Mở **Toolbox → IPA Signature**, thêm tệp `TamHoc-unsigned.ipa` đã giải nén.
3. Ký bằng Apple Account hoặc chứng chỉ/profile hợp lệ của chính bạn, dành cho iPhone cần cài. Nhập thông tin đăng nhập trực tiếp vào công cụ ký trên máy cá nhân; workflow này không cần Apple Account, chứng chỉ hay GitHub secret.
4. Chọn bản IPA **đã ký** ở vị trí đầu ra của công cụ ký, rồi cài qua **Apps → Import & Install IPA** (tên nút có thể khác theo phiên bản 3uTools).
5. Tin cậy nhà phát triển trên iPhone nếu được yêu cầu. Với Personal Team miễn phí, profile có hạn 7 ngày, cần ký/cài lại khi hết hạn. Giữ Bundle ID khi cập nhật để bảo toàn dữ liệu app.

Nếu ký/cài thất bại, gửi nguyên thông báo lỗi và phiên bản iOS/3uTools để phân biệt lỗi IPA với lỗi tài khoản/profile. GitHub Actions build thành công không đảm bảo dịch vụ ký bên thứ ba luôn hoạt động với mọi tài khoản.

## Phạm vi kiểm chứng

- Simulator trên GitHub dùng runtime được runner cung cấp, không khẳng định đã thử trên iOS 15.7.x thật.
- Gói IPA được kiểm tra `MinimumOSVersion = 15.7`, nền tảng iPhoneOS và kiến trúc arm64 trước khi upload.
- Trên iPhone cần thử cấp quyền camera, hiệu chỉnh, phiên học ngắn, khóa/thoát Guided Access, chuyển nền và lưu lịch sử.
- Test/build Swift và đóng gói IPA thực tế chưa chạy tại thời điểm tạo workflow trên Windows. Lần chạy GitHub đầu tiên mới cung cấp kết quả Xcode thật.
- Workflow chỉ tạo artifact, không xuất bản lên App Store hay GitHub Releases. Artifact/log giữ 7 ngày; push mới trên cùng nhánh sẽ hủy run cũ đang chạy để tiết kiệm hạn mức.
- Runner cố định Xcode 16.4 để dễ tái hiện. Nếu GitHub gỡ phiên bản này, cập nhật `DEVELOPER_DIR`/runner sau khi đối chiếu bảng image; không nâng minimum iOS để né lỗi.

## Đối chiếu tài liệu BUILD.md hiện có

`scripts/archive.sh` là luồng archive/export **có ký** và yêu cầu Team/Profile. Workflow mới độc lập: build `.app` cho iPhone rồi đóng gói **IPA chưa ký để ký lại ở Windows**. Vì vậy lời nhắc “unsigned artifact không cài được trực tiếp” vẫn đúng; nó không ngăn việc tạo gói IPA đúng cấu trúc làm đầu vào cho công cụ ký.

## Nguồn tham khảo

- Runner/Xcode: https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md
- Checkout: https://github.com/actions/checkout
- Artifact: https://github.com/actions/upload-artifact
- GitHub Actions billing: https://docs.github.com/en/billing/concepts/product-billing/github-actions
- Ký IPA: https://www.3u.com/tutorial/articles/12092/
- Personal Team: https://developer.apple.com/help/account/basics/about-your-developer-account
