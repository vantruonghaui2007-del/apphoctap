# Review Handoff — Tâm Học (iOS)

**Ngày cập nhật:** 24/11/2026  
**Nhánh Git:** `main`  
**Base code commit trước docs update:** `343d32d` (`56` tệp `.swift`, SHA-256 snapshot các tệp Swift theo thứ tự đường dẫn tương đối UTF-8 + nội dung: `37d38c1d80ab060f081d3e2f8138f0dc283b41008af61e5aa75402bf4a0da0bd`)  
**Phạm vi đã triển khai:** Task 1–10 trong [docs/superpowers/plans/2026-11-24-tamhoc-ios.md](superpowers/plans/2026-11-24-tamhoc-ios.md), các bản sửa R1–R6 (Review v1), V2-1..V2-4 (Review v2), V3-1..V3-2 (Review v3) và V4-1 (Review v4).  
**Phạm vi ngoài bản đầu:** Task 11 (Managed Single App MDM) và Task 12 (Screen Time iOS 16+) chưa bật/chưa thêm capability.

---

## 1. Bản sửa sau Review v4 (`V4-1`)
| Mã | Mức độ | Commit | Nội dung đã sửa & Kiểm chứng cần chạy trên Mac |
|---|---|---|---|
| **V4-1** | P1 | `343d32d` | Trong `TamHocTests/GuidedAccessTests.swift` (`awaitFirstStreamValue`), `readerTask` có kiểu `Task<Bool?, Never>` nên `BoundedAsyncWaiter.waitForTask<T>` trả `Bool??`. Đã lưu kết quả rõ kiểu `let result: Bool?? = await BoundedAsyncWaiter.waitForTask(...)` và trả `result ?? nil` để xử lý lớp optional bên ngoài về `Bool?` đúng chữ ký hàm: giữ nguyên `false`/`true` khi nhận được sự kiện (không dùng `?? false`), ánh xạ timeout (outer `nil`) và stream đóng trống (inner `nil`) về `nil`, đồng thời giữ nguyên `onTimeout: { readerTask.cancel() }`. Trên Mac cần build target `TamHocTests` và chạy tối thiểu `testReadingIsEnabledBeforeNotificationDoesNotDropChangeEvent` cùng `testStreamWaitTimeoutExitsPromptlyAndCleansUpSubscriberWhenNoNotificationPosted` (hiện **NOT RUN** trên Windows). |

---

## 2. Lịch sử sửa Review v3 (`V3-1`–`V3-2`), Review v2 (`V2-1`–`V2-4`) & Review v1 (`R1`–`R6`)
| Mã | Mức độ | Commit | Tóm tắt |
|---|---|---|---|
| **V3-1** | P1 | `e34f60c` | Tách toàn bộ 4 lời gọi `await presence.waitUntilStartSuspended()` ra khỏi synchronous `@autoclosure` của `XCTAssertTrue(...)` trong `TamHocTests/CoordinatorTests.swift`. |
| **V3-2** | P2 | `ef7e959` | Chuyển cơ chế chờ có timeout sang `OnceContinuationGate` + `@MainActor BoundedAsyncWaiter.waitForTask` độc lập với `TaskGroup`, kèm cleanup chủ động một lần trên `FakePresenceMonitor` (`PendingSuspension` + `abortedSuspensionIDs`) và regression test `testBoundedWaitTimeoutExitsPromptlyWhenContinuationNeverResumedAndCleansUpOnce`. |
| **V2-1** | P1 | `14cd0e8` | Bỏ chuỗi chờ vòng tròn giữa `endEarly()` và `resumeSuspendedStart()` trong `CoordinatorTests`. |
| **V2-2** | P1 | `fbd58d2` | Ranh giới đóng phiên `isFinalizing` cho cả 5 lý do kết thúc + cleanup camera theo ownership token `stop(generation:)`. |
| **V2-3** | P2 | `c3fa0fb` | Kiểm tra `driver.isRunning` và gắn observer `runtimeErrorNotification` theo `object` trước `startRunning()`. |
| **V2-4** | P2 | `6de331b` | Hủy đúng vòng chờ `AsyncStream` và gỡ subscriber khi hết hạn chờ trong `GuidedAccessTests`. |
| **R1–R6** | P1/P2 | `4dffec1`..`d33e068` | Tách throttle/inflight test, camera run-token & post-await lifecycle check, `isEnabled` read-only, xóa retain cycle `for await`, và chặn `thermalCritical` trước phiên. |

---

## 3. Trạng thái Môi trường & Kết Quả Kiểm Chứng
- **Môi trường phát triển đã chạy:** Windows (`T:\apphoctap`), Python 3.13.16, Git 2.55.0.
- **macOS / Xcode / Swift / iOS SDK:** **NOT RUN — requires macOS/Xcode**. Chưa biên dịch Swift, chưa mở Xcode và chưa chạy XCTest thực tế.
- **Thiết bị iPhone thật & IPA:** **NOT RUN / BLOCKED**.

| Kiểm tra | Lệnh | Kết quả | Ghi chú |
|---|---|---|---|
| Kiểm tra cấu trúc repo, pbxproj, XML/plist/JSON, Info.plist, PrivacyInfo, xcconfig, LF script, không lộ secret/private API, không `await` trong `XCTAssert*` | Static Python validator (Windows) | PASS | Kiểm tra tĩnh mã nguồn — **không** thay thế biên dịch Swift hay XCTest |
| Package domain tests (`StudyCoreTests`) | `swift test --package-path Packages/StudyCore` | NOT RUN (requires macOS/Swift) | 17 test methods khai báo ở 3 suite |
| Build Simulator (Debug, unsigned) | `xcodebuild ... -configuration Debug ... CODE_SIGNING_ALLOWED=NO build` | NOT RUN (requires macOS/Xcode) | Khai báo trong `scripts/verify.sh` |
| Build Device (Release, unsigned) | `xcodebuild ... -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` | NOT RUN (requires macOS/Xcode) | Khai báo trong `scripts/verify.sh` |
| Native Unit & UI Tests (`TamHocTests`, `TamHocUITests`) | `xcodebuild ... test` | NOT RUN (requires macOS/Xcode) | 57 unit test methods ở 7 suite & 6 UI test methods ở 4 suite (tổng **80** XCTest methods khai báo toàn repo; **chưa chạy Xcode**) |
| Archive & Export Signed IPA | `./scripts/archive.sh` | BLOCKED (requires macOS/Xcode + Signing Team/Profile) | Không tạo IPA giả |
| Cài đặt qua 3uTools & thử thiết bị thật | 3uTools Import & Install IPA | NOT RUN / UNVERIFIED | Cần IPA ký hợp lệ và iPhone thật |

---

## 4. Phần dùng Fake/Mock (chỉ trong Tests / Debug UITest)
- **Trong `Release`:** Không có đường giả lập khóa hoặc camera (`AppEnvironment.isUITestHarnessEnabled` trả `false` trong `#if !DEBUG`, toàn bộ harness nằm trong `#if DEBUG`).
- **Trong `TamHocTests`:** `FakeClock`, `FakeGuidedAccessMonitor`, `FakePresenceMonitor`, `FakeCameraAuthorizer`, `FakeCaptureSessionDriver`, `SpyWarningPlayer`, `MockSessionRepository`, `FakeIdleTimerController`, `FakeBackgroundTaskManager`, `OnceContinuationGate`, `BoundedAsyncWaiter`.
- **Trong `TamHocUITests` (`-uitest` chỉ compile ở `DEBUG`):** `UITestCameraAuthorizer` và `GuidedAccessMonitor` injected qua launch arguments.

## 5. Vấn đề & Release Gates còn mở
1. **Chưa biên dịch và chạy test trên macOS/Xcode (`NOT RUN`):** cần chạy `./scripts/verify.sh` trên máy Mac để xác nhận 0 lỗi biên dịch và chạy thực tế toàn bộ 80 XCTest methods trên iOS 15.7 và iOS mới hơn.
2. **Guided Access & Camera trên máy thật (`UNVERIFIED`):** cần chạy ma trận thử nghiệm trong `docs/DEVICE_TESTS.md` và `docs/RECOVERY.md` trên iPhone iOS 15.7.x và iOS mới hơn.
3. **Ký IPA & Cài 3uTools (`BLOCKED`):** cần Team/Provisioning hợp lệ trên macOS để chạy `./scripts/archive.sh`.
