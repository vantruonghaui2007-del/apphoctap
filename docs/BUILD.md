# Hướng dẫn Build, Ký IPA & Cài 3uTools — Tâm Học (iOS)

## Môi trường hiện tại
- **Môi trường tạo mã nguồn:** Windows (`T:\apphoctap`), Python 3.13.16, Git 2.55.0.
- **Trạng thái macOS / Xcode:** **NOT RUN — requires macOS/Xcode**. Chưa build, archive hay ký IPA thực tế tại máy Windows này.

## Yêu cầu Toolchain trên macOS
- **Deployment Target:** `IPHONEOS_DEPLOYMENT_TARGET = 15.7` (`arm64` cho thiết bị thật, iPhone only).
- **Ngôn ngữ:** Swift 5 (`SWIFT_VERSION = 5.0`), không thư viện bên thứ ba.
- **Chọn Xcode cho thiết bị 15.7 thật (`S1`):**
  - Một số phiên bản Xcode mới hơn vẫn biên dịch deployment target `15.7` nhưng không còn hỗ trợ gỡ lỗi trực tiếp qua cáp trên thiết bị iOS 15.x.
  - Khuyến nghị ghi rõ phiên bản Xcode/SDK dùng trên máy Mac (ví dụ một bản Xcode 14.x nếu cần debug cáp trực tiếp iPhone iOS 15.7.x và bản Xcode mới hơn cho iOS hiện tại), **không** sửa target lên 16/17 để né lỗi toolchain.

## 1. Kiểm chứng & chạy test trên macOS
```bash
./scripts/verify.sh
```
Hoặc chạy từng lệnh chuẩn:
```bash
xcodebuild -version
xcrun swift --version
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -showdestinations
swift test --package-path Packages/StudyCore
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

export TAMHOC_SIMULATOR_ID="<UDID_SIMULATOR>"
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -destination "platform=iOS Simulator,id=$TAMHOC_SIMULATOR_ID" -resultBundlePath artifacts/Tests.xcresult test
```

## 2. Archive & Ký IPA (cài ngoài App Store)
- **Bundle ID:** Mặc định trong `Config/*.xcconfig` là `vn.tamhoc.app`. Khi ký bằng tài khoản của bạn, đổi sang reverse-DNS thuộc team của bạn và giữ cố định qua các bản cập nhật để iOS giữ nguyên dữ liệu lịch sử trong Application Support.
- **Không đổi `.zip`/`.app` unsigned thành `.ipa`:** Lệnh compile với `CODE_SIGNING_ALLOWED=NO` hoặc `TAMHOC_UNSIGNED=1 ./scripts/archive.sh` chỉ tạo artifact không ký để kiểm tra biên dịch, không cài được lên iPhone.
- **Tạo `ExportOptions.plist` trên máy Mac:** Không sao chép cứng tên `method` từ Xcode đời khác (Xcode 14 dùng `development` / `ad-hoc`, Xcode 15+ dùng `debugging` / `release-testing`). Hãy export một lần từ Xcode Organizer trên chính máy Mac host để tạo `ExportOptions.plist`, hoặc điều chỉnh `Config/ExportOptions.template.plist` đúng với phiên bản Xcode đó (không commit file chứa Team ID thật).
- **Chạy archive + export IPA có ký:**
```bash
export TAMHOC_TEAM_ID="<YOUR_TEAM_ID>"
export TAMHOC_BUNDLE_ID="<YOUR_REVERSE_DNS_BUNDLE_ID>"
export TAMHOC_EXPORT_OPTIONS_PLIST="/path/to/ExportOptions.plist"
./scripts/archive.sh
```
`archive.sh` sẽ tự kiểm tra `MinimumOSVersion = 15.7`, kiến trúc `arm64`, `embedded.mobileprovision` và hạn profile (không in danh sách UDID ra log).

## 3. Lưu ý Personal Team (Apple ID miễn phí) & 3uTools
- **Personal Team (`S9`):** Provisioning profile thường chỉ có hạn **7 ngày** và Xcode thường chỉ hỗ trợ cài trực tiếp qua cáp (`Product > Run` / Device install), không cho export Ad Hoc IPA phân phối rộng rãi. Nếu Xcode không xuất được IPA theo luồng này, cần báo rõ chỉ test-install trực tiếp được.
- **Ký lại / cài bằng 3uTools (`S11`):**
  - Với IPA đã ký hợp lệ (hoặc ký lại trong 3uTools bằng Apple ID/quyền phù hợp của chính bạn — không dán mật khẩu vào script/chat):
  - Kết nối iPhone -> mục **Apps** -> **Import & Install IPA**.
  - Lần đầu mở app ngoài App Store: vào **Cài đặt > Cài đặt chung > Quản lý VPN & Thiết bị** để Tin cậy (Trust) chứng chỉ nhà phát triển.
  - Không xem việc ký/cài thành công là đã kiểm chứng xong; vẫn phải thử mở app, hiệu chỉnh camera, bật/thoát Guided Access và cập nhật đè cùng Bundle ID để xác nhận còn nguyên lịch sử.

## 4. Đóng gói gửi Review (không kèm secrets)
```bash
./scripts/package-review.sh
```
Xuất ra `artifacts/TamHoc-review.zip` chỉ chứa mã nguồn, `TamHoc.xcodeproj` + shared scheme, `Config/`, `Packages/`, tests, scripts và docs; loại bỏ `DerivedData`, `.p12`, `.p8`, profiles, secrets, `.xcuserstate` và không có ảnh/video camera.
