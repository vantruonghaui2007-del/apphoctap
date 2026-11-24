# Review Handoff — Tâm Học (iOS)

**Ngày cập nhật:** 24/11/2026  
**Nhánh Git:** `main`  
**Base code commit trước docs update:** `6de331b` (`56` tệp `.swift`, SHA-256 snapshot các tệp Swift theo thứ tự đường dẫn tương đối UTF-8 + nội dung: `b382e52bed37834ff5fdacf8ccc0c90e3165902b101edbb346b760a51572ec90`)  
**Phạm vi đã triển khai:** Task 1–10 trong [docs/superpowers/plans/2026-11-24-tamhoc-ios.md](superpowers/plans/2026-11-24-tamhoc-ios.md), các bản sửa R1–R6 (Review v1) và V2-1..V2-4 (Review v2).  
**Phạm vi ngoài bản đầu:** Task 11 (Managed Single App MDM) và Task 12 (Screen Time iOS 16+) chưa bật/chưa thêm capability.

---

## 1. Các bản sửa sau Review v2 (`V2-1`–`V2-4`)
| Mã | Mức độ | Commit | Nội dung đã sửa & Regression Test bổ sung |
|---|---|---|---|
| **V2-1** | P1 | `14cd0e8` | Loại bỏ chuỗi chờ vòng tròn trong `CoordinatorTests.testResumeCameraStartSuspendedThenEndEarlyLeavesCameraStopped`: chạy `endEarly()` ở task riêng, chờ tín hiệu phiên chuyển terminal có timeout hữu hạn rồi mới `resumeSuspendedStart()` và await kết thúc với `awaitTaskWithTimeout`; bổ sung timeout & `defer { releaseAllSuspendedStarts() }` cho `FakePresenceMonitor.waitUntilStartSuspended`. |
| **V2-2** | P1 | `fbd58d2` | Tạo ranh giới đóng phiên thật (`isFinalizing` công bố qua `@Published`, chặn `start()` mới bằng `CoordinatorError.previousSessionFinalizing`, thống nhất cả 5 đường thoát `deadline`/`userEnded`/`lockReleased`/`storageFailure`/`clockFailure` và reset `isFinalizing = false` trong `defer` khi cleanup xong; `CompletionView` vẫn giữ nút hướng dẫn thoát mở ngay nhưng khóa nút bắt đầu phiên mới khi đang dọn tài nguyên). Thêm cleanup theo ownership token (`stop(generation:)`, `deactivateIfMatching(token:)`, `deactivateIfMatching(generation:)`) tại `CameraPresenceMonitor` để task phiên cũ không thể dừng camera của phiên mới. Thêm `testSessionBCannotStartWhileSessionAFinalizationPendingThenRunsCleanly`, `testAllTerminalReasonsResetIsFinalizingForSubsequentSessions`, `testDeactivateIfMatchingTokenPreservesNewerRunToken`. |
| **V2-3** | P2 | `c3fa0fb` | Thêm `CaptureSessionDriving` / `AVCaptureSessionDriver` và `StartupErrorTracker` trong `CameraPresenceMonitor`: gắn observer `runtimeErrorNotification` và `wasInterruptedNotification` theo đúng `object` của session **trước** khi gọi `startRunning()`; chỉ xác nhận start thành công khi `driver.isRunning == true` và không phát sinh lỗi runtime trong pha khởi động, ngược lại dọn tài nguyên và ném `PresenceMonitorError.cameraUnavailable`. Thêm `testCameraStartFailsWhenCaptureFailsToRunOrPostsImmediateRuntimeError` và `testCoordinatorDoesNotCommitRunningWhenCaptureReadinessFails`. |
| **V2-4** | P2 | `6de331b` | Bỏ unstructured `receivedTask` trong `GuidedAccessTests`: dùng structured child trực tiếp trong `withTaskGroup` (`awaitFirstStreamValue`) để `group.cancelAll()` hủy ngay vòng `for await` trên `AsyncStream` và gỡ subscriber khi hết hạn chờ. Thêm `testStreamWaitTimeoutExitsPromptlyAndCleansUpSubscriberWhenNoNotificationPosted` kiểm chứng trực tiếp nhánh không có notification thoát trong < 1.5s và `subscriberCount == 0`. |

---

## 2. Lịch sử sửa Review v1 (`R1`–`R6`)
| Mã | Mức độ | Commit | Tóm tắt |
|---|---|---|---|
| **R1** | P1 | `4dffec1` | Tách `InstantDetector` cho bài throttle khỏi `BlockingDetector` cho single-inflight, thêm timeout 2s + `defer` signal. |
| **R2 & R4** | P1/P2 | `2e5f3c8` | Thêm run-token camera, `resumeCameraTask` / `stopCameraTask`, và kiểm tra `currentActivity == .active` qua mọi `await`. |
| **R3** | P2 | `bf725f6` | Giữ `GuidedAccessMonitor.isEnabled` là phép đọc thuần túy, chỉ cập nhật `lastPublishedValue` khi phát sự kiện. |
| **R5** | P2 | `8a52be5` | Xóa retain cycle `for await` trong ViewModels/Coordinator và gắn `startObserving()`/`stopObserving()`. |
| **R6** | P2 | `d33e068` | Chặn `thermalState == .critical` trước khi vào phiên camera (`PresenceMonitorError.thermalCritical` / `CoordinatorError.thermalCritical`). |

---

## 3. Trạng thái Môi trường & Kết Quả Kiểm Chứng
- **Môi trường phát triển đã chạy:** Windows (`T:\apphoctap`), Python 3.13.16, Git 2.55.0.
- **macOS / Xcode / Swift / iOS SDK:** **NOT RUN — requires macOS/Xcode**. Không có máy Mac tại môi trường thực thi nên chưa chạy biên dịch Swift/Xcode hay chạy XCTest thực tế.
- **Thiết bị iPhone thật:** **NOT RUN / BLOCKED**.

| Kiểm tra | Lệnh | Kết quả | Ghi chú |
|---|---|---|---|
| Kiểm tra cấu trúc repo, pbxproj, XML/plist/JSON, Info.plist, PrivacyInfo, xcconfig, LF script, không lộ secret/private API | Static Python validator (Windows) | PASS | Đã chạy sau tất cả các bản sửa |
| Package domain tests (`StudyCoreTests`) | `swift test --package-path Packages/StudyCore` | NOT RUN (requires macOS/Swift) | 17 test methods ở 3 suite |
| Build Simulator (Debug, unsigned) | `xcodebuild ... -configuration Debug ... CODE_SIGNING_ALLOWED=NO build` | NOT RUN (requires macOS/Xcode) | Khai báo trong `scripts/verify.sh` |
| Build Device (Release, unsigned) | `xcodebuild ... -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` | NOT RUN (requires macOS/Xcode) | Khai báo trong `scripts/verify.sh` |
| Native Unit & UI Tests (`TamHocTests`, `TamHocUITests`) | `xcodebuild ... test` | NOT RUN (requires macOS/Xcode) | 56 unit test methods ở 7 suite & 6 UI test methods ở 4 suite (tổng **79** XCTest methods khai báo toàn repo; **chưa chạy Xcode**) |
| Archive & Export Signed IPA | `./scripts/archive.sh` | BLOCKED (requires macOS/Xcode + Signing Team/Profile) | Không tạo IPA giả |
| Cài đặt qua 3uTools & thử thiết bị thật | 3uTools Import & Install IPA | NOT RUN / UNVERIFIED | Cần IPA ký hợp lệ và iPhone thật |

---

## 4. Phần dùng Fake/Mock (chỉ trong Tests / Debug UITest)
- **Trong `Release`:** Không có đường giả lập khóa hoặc camera (`AppEnvironment.isUITestHarnessEnabled` trả `false` trong `#if !DEBUG`, toàn bộ harness nằm trong `#if DEBUG`).
- **Trong `TamHocTests`:** `FakeClock`, `FakeGuidedAccessMonitor`, `FakePresenceMonitor`, `FakeCameraAuthorizer`, `FakeCaptureSessionDriver`, `SpyWarningPlayer`, `MockSessionRepository`, `FakeIdleTimerController`, `FakeBackgroundTaskManager`.
- **Trong `TamHocUITests` (`-uitest` chỉ compile ở `DEBUG`):** `UITestCameraAuthorizer` và `GuidedAccessMonitor` injected qua launch arguments.

## 5. Vấn đề & Release Gates còn mở
1. **Chưa biên dịch và chạy test trên macOS/Xcode:** cần chạy `./scripts/verify.sh` trên máy Mac để xác nhận 0 lỗi biên dịch và toàn bộ 79 XCTest methods PASS trên iOS 15.7 và iOS mới hơn.
2. **Guided Access & Camera trên máy thật (`UNVERIFIED`):** cần chạy ma trận thử nghiệm trong `docs/DEVICE_TESTS.md` và `docs/RECOVERY.md` trên iPhone iOS 15.7.x và iOS mới hơn.
3. **Ký IPA & Cài 3uTools (`BLOCKED`):** cần Team/Provisioning hợp lệ trên macOS để chạy `./scripts/archive.sh`.
