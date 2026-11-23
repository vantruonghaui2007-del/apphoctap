# Review Handoff — Tâm Học (iOS)

**Ngày bàn giao:** 24/11/2026  
**Nhánh Git:** `main` (xem `git log -n 12 --oneline` để lấy commit hash cuối cùng sau commit Task 10)  
**Phạm vi đã triển khai:** Task 1 đến Task 10 trong [docs/superpowers/plans/2026-11-24-tamhoc-ios.md](../docs/superpowers/plans/2026-11-24-tamhoc-ios.md).  
**Phạm vi ngoài bản đầu:** Task 11 (Managed Single App MDM) và Task 12 (Screen Time iOS 16+) chưa bật/chưa thêm capability.

---

## 1. Trạng thái Môi trường & Toolchain
- **Môi trường phát triển đã chạy:** Windows (`T:\apphoctap`), Python 3.13.16, Git 2.55.0.
- **macOS / Xcode / Swift / iOS SDK:** **NOT RUN — requires macOS/Xcode**. Không có máy Mac tại môi trường thực thi nên không có số phiên bản Xcode/Swift hay Simulator UDID thực tế đã chạy.
- **Thiết bị iPhone thật:** **NOT RUN / BLOCKED** (chưa có iPhone iOS 15.7.x hoặc iPhone iOS mới hơn kết nối để thử).

## 2. Bảng Lệnh Kiểm Chứng & Kết Quả
| Kiểm tra | Lệnh | Kết quả | Ghi chú |
|---|---|---|---|
| Kiểm tra cấu trúc repo, pbxproj, XML/plist/JSON, Info.plist, xcconfig, không lộ secret/private API | Static Python validator (Windows) | PASS | Đã chạy qua từng task |
| Package domain tests (`StudyCoreTests`) | `swift test --package-path Packages/StudyCore` | NOT RUN (requires macOS/Swift) | Đã viết 17 test methods ở 3 suite (`TimelineLedgerTests`, `PresencePolicyTests`, `SessionEngineTests`) |
| Build Simulator (Debug, unsigned) | `xcodebuild ... -configuration Debug ... CODE_SIGNING_ALLOWED=NO build` | NOT RUN (requires macOS/Xcode) | Khai báo trong `scripts/verify.sh` |
| Build Device (Release, unsigned) | `xcodebuild ... -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` | NOT RUN (requires macOS/Xcode) | Khai báo trong `scripts/verify.sh` |
| Native Unit & UI Tests (`TamHocTests`, `TamHocUITests`) | `xcodebuild ... test` | NOT RUN (requires macOS/Xcode) | Đã viết 39 unit test methods ở 7 suite & 6 UI test methods ở 4 suite (tổng 62 XCTest methods toàn repo) |
| Archive & Export Signed IPA | `./scripts/archive.sh` | BLOCKED (requires macOS/Xcode + Signing Team/Profile) | Không tạo IPA giả hoặc đổi tên zip |
| Cài đặt qua 3uTools & thử thiết bị thật | 3uTools Import & Install IPA | NOT RUN / UNVERIFIED | Cần IPA ký hợp lệ và iPhone thật |

## 3. Tóm tắt Kiến trúc & Hợp đồng đã triển khai
- **StudyCore (`Packages/StudyCore`)**:
  - `Models.swift`, `TimelineLedger.swift`, `PresencePolicy.swift`, `SessionEngine.swift`.
  - Đồng hồ monotonic độc lập wall-clock, hạch toán 5 bucket loại trừ nhau (`present`, `absent`, `unknown`, `unverified`, `ineligible`), ổn định 5s không cộng bù, TTL mẫu 3s, ngưỡng vắng 30s (1 cảnh báo/lần) & 60s, ngắt chuỗi vắng khi mất quan sát, terminal bất biến.
- **Platform & Lock (`TamHoc/Platform`, `TamHoc/Lock`)**:
  - `SystemSessionClock.swift`: `mach_continuous_time()` + kiểm tra timebase.
  - `GuidedAccessMonitor.swift`: đọc thật `UIAccessibility.isGuidedAccessEnabled` và lắng nghe notification để đọc lại boolean.
  - `AppActivityMonitor.swift`: gộp sự kiện vòng đời UIKit & `ScenePhase`, khử trùng lặp, không gán nhãn tên app ngoài.
- **Presence & Camera (`TamHoc/Presence`)**:
  - `Calibration.swift`, `PreviewGeometry.swift`: ánh xạ ROI portrait `.resizeAspectFill` kèm mirror front camera.
  - `VisionPersonDetector.swift`: đo luminance (`< 0.08` -> `.unknown(.lowLight)`), `VNDetectHumanRectanglesRequest` (`upperBodyOnly = true`), fallback `VNDetectFaceRectanglesRequest`, ngưỡng `0.6`, không lưu ảnh/embedding.
  - `CameraPresenceMonitor.swift`: xin quyền chủ động khi dùng camera, serial capture queue, `alwaysDiscardsLateVideoFrames = true`, single inflight frame, 2 Hz bình thường / 1 Hz `.serious` / dừng ở `.critical`, cô lập `generation`.
- **Storage, Recovery, Export & Retention (`TamHoc/Storage`, `TamHoc/Export`)**:
  - `FileSessionRepository.swift`: actor atomic write, tên file UUID, revision guard, cách ly file hỏng vào `Quarantine/`, giữ nguyên schema tương lai (`!= 1`) chỉ đọc.
  - `SettingsRepository.swift`, `SessionRecovery.swift`, `RetentionPolicy.swift` (prune `events` quá 30 ngày theo ngày trong record, giữ totals & bảo vệ khi clock lùi), `SessionExporter.swift` (CSV neutralized formula injection + JSON, không clock thô/ảnh).
- **Coordinator & UI (`TamHoc/Session`, `TamHoc/Features`, `TamHoc/Design`)**:
  - `SessionCoordinator.swift`: `@MainActor`, hàng đợi lưu tuần tự chống ghi đè terminal, hủy start an toàn khi đang await camera, dừng camera khi inactive/background, hết hạn vẫn hoàn thành đúng deadline, xử lý `clockFailure` & `thermalLimit`.
  - Giao diện SwiftUI tiếng Việt, Light/Dark, Dynamic Type + `AdaptiveStack`, `AppNavigationContainer` hỗ trợ iOS 15.7 (`NavigationView`) và iOS 16+ (`NavigationStack`), `UIActivityViewController` cho Share Sheet iOS 15.7+.

## 4. Phần dùng Fake/Mock (chỉ trong Tests / Debug UITest)
- **Trong `Release`:** Không có bất kỳ đường giả lập khóa hoặc camera nào (`AppEnvironment.isUITestHarnessEnabled` trả `false` trong `#if !DEBUG`, toàn bộ harness nằm trong `#if DEBUG`).
- **Trong `TamHocTests`:** `FakeClock`, `FakeGuidedAccessMonitor`, `FakePresenceMonitor`, `FakeCameraAuthorizer`, `SpyWarningPlayer`, `MockSessionRepository`, `FakeIdleTimerController`, `FakeBackgroundTaskManager`.
- **Trong `TamHocUITests` (`-uitest` chỉ compile ở `DEBUG`):** `UITestCameraAuthorizer` và `GuidedAccessMonitor` injected qua launch arguments (`-uitest-lock-on`, `-uitest-camera-denied`, `-uitest-show-onboarding`).

## 5. Vấn đề & Release Gates còn mở (Bắt buộc trước khi dùng chính thức)
1. **Chưa biên dịch và chạy test trên macOS/Xcode:** cần chạy `./scripts/verify.sh` trên máy Mac để xác nhận 0 lỗi biên dịch và toàn bộ unit/UI tests PASS trên iOS 15.7 và iOS mới hơn.
2. **Guided Access trên máy thật (`UNVERIFIED`):** cần xác minh thực tế trên iPhone iOS 15.7.x và iPhone iOS mới hơn các kịch bản vào/ra khóa, sai mã, kill app và reboot (`docs/DEVICE_TESTS.md`, `docs/RECOVERY.md`).
3. **Độ chính xác & nhiệt camera (`UNVERIFIED`):** cần đo trên iPhone thật bài rời bàn >= 19/20 lần, 2 giờ học giấy <= 1 false alarm và phiên 50 phút peak memory < 150MB bằng Instruments.
4. **Ký IPA & Cài 3uTools (`BLOCKED`):** cần Team/Provisioning hợp lệ của người dùng trên macOS để chạy `./scripts/archive.sh` và kiểm chứng cài đặt thực tế.
