# Review Handoff — Tâm Học (iOS)

**Ngày cập nhật:** 24/11/2026  
**Nhánh Git:** `main`  
**Base code commit trước docs update:** `d33e068` (`56` tệp `.swift`, SHA-256 snapshot các tệp Swift theo thứ tự đường dẫn tương đối UTF-8 + nội dung: `2d884e1622e4ade6ba4954160b447e8dbb42140530424102ce9a98d1eaa5ff41`)  
**Phạm vi đã triển khai:** Task 1–10 trong [docs/superpowers/plans/2026-11-24-tamhoc-ios.md](superpowers/plans/2026-11-24-tamhoc-ios.md) và các bản sửa review R1–R6.  
**Phạm vi ngoài bản đầu:** Task 11 (Managed Single App MDM) và Task 12 (Screen Time iOS 16+) chưa bật/chưa thêm capability.

---

## 1. Các bản sửa sau Review (R1–R6)
| Mã | Mức độ | Commit | Nội dung đã sửa & Regression Test bổ sung |
|---|---|---|---|
| **R1** | P1 | `4dffec1` | Tách `testSingleInflightFrameDropsOverlappingFrames` khỏi `testSampleThrottleNormalAndSeriousThermal` (không dùng detector block cho throttle), thêm timeout 2s + `defer { signal() }` cho mọi semaphore/group wait trong `PresenceTests.swift`. |
| **R2** | P1 | `2e5f3c8` | Thêm ownership run-token (`desiredRunToken`, `pendingRunToken`, `activeRunToken`, `activeCaptureToken`) và `stopSessionOnQueue` nối tiếp trên serial `captureQueue` trong `CameraPresenceMonitor`; lưu và hủy `resumeCameraTask` + nối tiếp `stopCameraTask` trong `SessionCoordinator`; tách capture-run token mới cho mỗi lần restart. Thêm `testResumeCameraStartSuspendedThenEndEarlyLeavesCameraStopped` và `testResumeCameraStartSuspendedThenInactiveStopsCameraAndUsesNewRunToken`. |
| **R4** | P2 | `2e5f3c8` | Không tự ép `currentActivity = .active` trong `SessionCoordinator.start`; kiểm tra `currentActivity == .active` trước/sau mọi `await` và hủy pending start ngay khi nhận `inactive`/`background` ngoài foreground. Thêm `testInactiveDuringPendingStartCancelsStartWithoutFakeRunningOrCamera`. |
| **R3** | P2 | `bf725f6` | Giữ `GuidedAccessMonitor.isEnabled` là phép đọc thuần túy không sửa `lastPublishedValue`; chỉ `refreshFromSystem()` cập nhật `lastPublishedValue` và phát event. Thêm `testReadingIsEnabledBeforeNotificationDoesNotDropChangeEvent`. |
| **R5** | P2 | `8a52be5` | Loại bỏ retain cycle `Task { [weak self] in guard let self = self; for await ... }` tại `PreflightViewModel`, `SessionViewModel`, `CalibrationViewModel` và `SessionCoordinator`: lấy stream trước khi vào Task và chỉ unwrap `weak self` trong từng vòng lặp; bổ sung `startObserving()`/`stopObserving()` gắn vòng đời `PreflightView`. Thêm `testPreflightViewModelDeallocatesAndUnsubscribesWithoutRetainCycle`, `testPreflightViewModelStopObservingRemovesSubscriberOnDisappear`, `testSessionViewModelDeallocatesWithoutRetainCycle`. |
| **R6** | P2 | `d33e068` | Thêm `PresenceMonitorError.thermalCritical` và `CoordinatorError.thermalCritical`: `CameraPresenceMonitor.start` từ chối khi `thermalState == .critical` thay vì return success; `SessionCoordinator.start` kiểm tra `thermalStateProvider() != .critical` tại preflight, sau save, và lắng nghe sự kiện `.unknown(.thermal)` phát ra trong lúc `start` trước khi commit `.running`. Thêm `testCameraStartRejectsWhenThermalCritical`, `testStartRejectsWhenThermalCriticalAtPreflight`, `testStartRejectsWhenMonitorEmitsThermalDuringStart`. |

---

## 2. Trạng thái Môi trường & Toolchain
- **Môi trường phát triển đã chạy:** Windows (`T:\apphoctap`), Python 3.13.16, Git 2.55.0.
- **macOS / Xcode / Swift / iOS SDK:** **NOT RUN — requires macOS/Xcode**. Không có máy Mac tại môi trường thực thi nên chưa chạy biên dịch Swift/Xcode hay chạy XCTest thực tế.
- **Thiết bị iPhone thật:** **NOT RUN / BLOCKED** (chưa có iPhone iOS 15.7.x hoặc iPhone iOS mới hơn kết nối để thử).

## 3. Bảng Lệnh Kiểm Chứng & Kết Quả
| Kiểm tra | Lệnh | Kết quả | Ghi chú |
|---|---|---|---|
| Kiểm tra cấu trúc repo, pbxproj, XML/plist/JSON, Info.plist, PrivacyInfo, xcconfig, LF script, không lộ secret/private API | Static Python validator (Windows) | PASS | Chạy sau mỗi bản sửa |
| Package domain tests (`StudyCoreTests`) | `swift test --package-path Packages/StudyCore` | NOT RUN (requires macOS/Swift) | 17 test methods ở 3 suite (`TimelineLedgerTests`, `PresencePolicyTests`, `SessionEngineTests`) |
| Build Simulator (Debug, unsigned) | `xcodebuild ... -configuration Debug ... CODE_SIGNING_ALLOWED=NO build` | NOT RUN (requires macOS/Xcode) | Khai báo trong `scripts/verify.sh` |
| Build Device (Release, unsigned) | `xcodebuild ... -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` | NOT RUN (requires macOS/Xcode) | Khai báo trong `scripts/verify.sh` |
| Native Unit & UI Tests (`TamHocTests`, `TamHocUITests`) | `xcodebuild ... test` | NOT RUN (requires macOS/Xcode) | 50 unit test methods ở 7 suite & 6 UI test methods ở 4 suite (tổng **73** XCTest methods khai báo toàn repo) |
| Archive & Export Signed IPA | `./scripts/archive.sh` | BLOCKED (requires macOS/Xcode + Signing Team/Profile) | Không tạo IPA giả |
| Cài đặt qua 3uTools & thử thiết bị thật | 3uTools Import & Install IPA | NOT RUN / UNVERIFIED | Cần IPA ký hợp lệ và iPhone thật |

## 4. Phần dùng Fake/Mock (chỉ trong Tests / Debug UITest)
- **Trong `Release`:** Không có đường giả lập khóa hoặc camera (`AppEnvironment.isUITestHarnessEnabled` trả `false` trong `#if !DEBUG`, toàn bộ harness nằm trong `#if DEBUG`).
- **Trong `TamHocTests`:** `FakeClock`, `FakeGuidedAccessMonitor`, `FakePresenceMonitor`, `FakeCameraAuthorizer`, `SpyWarningPlayer`, `MockSessionRepository`, `FakeIdleTimerController`, `FakeBackgroundTaskManager`.
- **Trong `TamHocUITests` (`-uitest` chỉ compile ở `DEBUG`):** `UITestCameraAuthorizer` và `GuidedAccessMonitor` injected qua launch arguments (`-uitest-lock-on`, `-uitest-camera-denied`, `-uitest-show-onboarding`).

## 5. Vấn đề & Release Gates còn mở (Bắt buộc trước khi dùng chính thức)
1. **Chưa biên dịch và chạy test trên macOS/Xcode:** cần chạy `./scripts/verify.sh` trên máy Mac để xác nhận 0 lỗi biên dịch và toàn bộ 73 XCTest methods PASS trên iOS 15.7 và iOS mới hơn.
2. **Guided Access trên máy thật (`UNVERIFIED`):** cần xác minh thực tế trên iPhone iOS 15.7.x và iPhone iOS mới hơn các kịch bản vào/ra khóa, sai mã, kill app và reboot (`docs/DEVICE_TESTS.md`, `docs/RECOVERY.md`).
3. **Độ chính xác & nhiệt camera (`UNVERIFIED`):** cần đo trên iPhone thật bài rời bàn >= 19/20 lần, 2 giờ học giấy <= 1 false alarm và phiên 50 phút peak memory < 150MB bằng Instruments.
4. **Ký IPA & Cài 3uTools (`BLOCKED`):** cần Team/Provisioning hợp lệ của người dùng trên macOS để chạy `./scripts/archive.sh` và kiểm chứng cài đặt thực tế.
