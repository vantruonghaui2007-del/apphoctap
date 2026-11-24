# Review Handoff — Tâm Học (iOS)

**Ngày cập nhật:** 24/11/2026  
**Nhánh Git:** `main`  
**Base code commit trước docs update:** `ef7e959` (`56` tệp `.swift`, SHA-256 snapshot các tệp Swift theo thứ tự đường dẫn tương đối UTF-8 + nội dung: `a69a14798c12575dfc7b78fc13d913cf3c03215307092dccc6142bba8300961f`)  
**Phạm vi đã triển khai:** Task 1–10 trong [docs/superpowers/plans/2026-11-24-tamhoc-ios.md](superpowers/plans/2026-11-24-tamhoc-ios.md), các bản sửa R1–R6 (Review v1), V2-1..V2-4 (Review v2) và V3-1..V3-2 (Review v3).  
**Phạm vi ngoài bản đầu:** Task 11 (Managed Single App MDM) và Task 12 (Screen Time iOS 16+) chưa bật/chưa thêm capability.

---

## 1. Các bản sửa sau Review v3 (`V3-1`, `V3-2`)
| Mã | Mức độ | Commit | Nội dung đã sửa & Regression Test bổ sung |
|---|---|---|---|
| **V3-1** | P1 | `e34f60c` | Tách toàn bộ 4 lời gọi `await presence.waitUntilStartSuspended()` ra khỏi synchronous `@autoclosure` của `XCTAssertTrue(...)` trong `TamHocTests/CoordinatorTests.swift`; rà soát bằng parser ngoặc trên toàn bộ 56 tệp `.swift` để xác nhận không còn bất kỳ `XCTAssert*`/`XCTUnwrap` nào chứa `await` bên trong biểu thức đối số. |
| **V3-2** | P2 | `ef7e959` | Thiết kế lại cơ chế chờ có giới hạn thời gian thực sự (`OnceContinuationGate` + `@MainActor BoundedAsyncWaiter.waitForTask` trong `TamHocTests/TestDoubles.swift`): không đặt `await task.value` làm child của `TaskGroup`, nên khi hết hạn chờ hàm trả `nil` ngay lập tức dù tác vụ nền đang treo ở `CheckedContinuation` không tự hủy theo `Task.cancel()`, đồng thời gọi `onTimeout` cleanup chủ động trên `@MainActor`. Nâng cấp `FakePresenceMonitor` dùng hàng đợi `PendingSuspension` + `abortedSuspensionIDs` đảm bảo mỗi `CheckedContinuation` chỉ được `resume()` tối đa đúng một lần và ném `CancellationError` khi bị dọn dẹp do timeout; đồng bộ `GuidedAccessTests.awaitFirstStreamValue` sang `BoundedAsyncWaiter` trên `@MainActor` để giữ cô lập actor với `AsyncStream` trên cả Swift 5.7/5.8. Thêm regression test `testBoundedWaitTimeoutExitsPromptlyWhenContinuationNeverResumedAndCleansUpOnce` trong `CoordinatorTests.swift`. |

---

## 2. Lịch sử sửa Review v2 (`V2-1`–`V2-4`) & Review v1 (`R1`–`R6`)
| Mã | Mức độ | Commit | Tóm tắt |
|---|---|---|---|
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
