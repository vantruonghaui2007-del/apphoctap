# Hướng dẫn Build & Kiểm chứng — Tâm Học (iOS)

## Môi trường hiện tại
- **Môi trường phát triển đã dùng:** Windows (`T:\apphoctap`), Python 3.13.16, Git 2.55.0.
- **Trạng thái macOS / Xcode:** **NOT RUN — requires macOS/Xcode**. Không có máy Mac, Xcode, Swift toolchain hay iPhone kết nối tại môi trường tạo mã nguồn này.

## Yêu cầu Toolchain trên macOS
- **Deployment Target:** `IPHONEOS_DEPLOYMENT_TARGET = 15.7` (`arm64` cho thiết bị thật).
- **Ngôn ngữ:** Swift 5 (`SWIFT_VERSION = 5.0`), SwiftUI + UIKit + AVFoundation + Vision.
- **Khuyến nghị hai vai trò toolchain khi test iOS 15.7 thật:**
  - Theo tài liệu Xcode của Apple (`S1`), các bản Xcode quá mới có thể vẫn biên dịch deployment target 15.7 nhưng không còn hỗ trợ debug trực tiếp qua cáp trên thiết bị iOS 15.x.
  - Cần ghi rõ phiên bản Xcode/SDK thực tế dùng để build/archive và phiên bản Xcode (ví dụ Xcode 14.x nếu cần debug trực tiếp thiết bị iOS 15.7) trước khi ký nghiệm thu.
  - Tuyệt đối không nâng `IPHONEOS_DEPLOYMENT_TARGET` lên 16/17 để né lỗi toolchain.

## Lệnh build và test chuẩn (chạy trên macOS từ gốc repo)

```bash
xcodebuild -version
xcrun swift --version
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -showdestinations
swift test --package-path Packages/StudyCore
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Chạy test trên Simulator thực:

```bash
export TAMHOC_SIMULATOR_ID="<UDID_SIMULATOR_TU_SHOWDESTINATIONS>"
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -destination "platform=iOS Simulator,id=$TAMHOC_SIMULATOR_ID" -resultBundlePath artifacts/Tests.xcresult test
```

Hoặc dùng script tự động: `./scripts/verify.sh`.

## Bằng chứng đã chạy tại Task 1
- **Static & Config Checks (Windows):** PASS (kiểm tra `IPHONEOS_DEPLOYMENT_TARGET = 15.7`, `SWIFT_VERSION = 5.0`, `TARGETED_DEVICE_FAMILY = 1`, `NSCameraUsageDescription`, không chứa quyền micro/photos/location/background, không chứa secrets).
- **Swift / Xcode Build & Tests:** **NOT RUN — requires macOS/Xcode**.
