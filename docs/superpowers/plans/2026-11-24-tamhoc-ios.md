# Tâm Học iOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Bàn giao cụ thể:** người thực hiện là Antigravity. Nếu môi trường không có các sub-skill trên, thực hiện trực tiếp theo từng task, giữ nguyên các cổng kiểm chứng và báo cáo; không cần cài plugin chỉ để bắt đầu. Codex sẽ review mã nguồn sau, không phải người xây app trong lần bàn giao này.

**Goal:** Xây app iPhone cài ngoài App Store, hỗ trợ **iOS 15.7 trở lên**, giữ người dùng trong phiên học có đồng hồ và tùy chọn xác nhận hiện diện tại bàn bằng camera.

**Architecture:** Dùng Swift/SwiftUI native cho bản iOS này, UIKit cho Guided Access và vòng đời, AVFoundation/Vision cho camera. Lõi phiên học là Swift Package độc lập với UIKit để kiểm thử bằng thời gian giả. Bản mặc định dùng Guided Access do người dùng bật; tự bật/tắt khóa là nhánh managed có điều kiện riêng, không được giả lập thành công.

**Tech Stack:** Swift 5 language mode; SwiftUI, UIKit, AVFoundation, Vision, Foundation, XCTest/XCUITest; không thư viện bên thứ ba cho bản đầu. Deployment target `15.7`, kiến trúc thiết bị `arm64`.

**Spec:** Đặc tả iOS đầy đủ nằm trong mục “1. Đặc tả iOS được triển khai” của chính tài liệu này; khi đưa vào repo lưu tài liệu tại `docs/superpowers/plans/2026-11-24-tamhoc-ios.md`. Tài liệu này tự đủ để Antigravity triển khai. Thiết kế nguồn: [TamHoc_KeHoach_ThietKe_v1.md](https://chatgpt.com/library?file_id=libfile_a38dc86a05388191940a89d218995010&account_id=personal).

Ngày: 24/11/2026. Trạng thái: **kế hoạch triển khai, chưa có sản phẩm hoặc kết quả test thực tế**.

## Global Constraints

- **iOS 15.7 trở lên**; không giới hạn vào iPhone 7 và không đổi minimum target thành iOS 16/17 để né lỗi.
- Giao diện tiếng Việt, hiện đại, hỗ trợ Light/Dark Mode, Dynamic Type và VoiceOver.
- Mặc định **50 phút**; lựa chọn **2–180 phút** trước phiên; không sửa thời lượng trong phiên.
- Nhắc khi vắng **30 giây**, đánh dấu rời vị trí lâu ở **60 giây**, cần hiện diện ổn định **5 giây** để cộng tiếp.
- Tối đa **3 giây** giữ giá trị mẫu camera; quá hạn phải là “không thể xác nhận”.
- Chỉ phân tích camera tại máy; không lưu hoặc tải ảnh/video, không nhận diện danh tính, không quyền micro/GPS/Photos.
- Học ngoại tuyến; không bắt đăng ký, không backend, quảng cáo, thuê bao hoặc đồng bộ trong bản đầu.
- Chỉ chế độ đã kiểm chứng mới được gọi là khóa; full-screen không đồng nghĩa khóa hệ điều hành.
- Không root/jailbreak mới, private API, sửa firmware, giấu profile, cản tắt máy hoặc vô hiệu hóa cơ chế bảo vệ iOS.
- Không tự reset, enroll MDM hoặc thay chính sách thiết bị thật. Kế hoạch không phải sự đồng ý xóa dữ liệu.
- Guided Access thủ công **không được hứa tự thoát khi hết giờ**.
- Tính năng iOS mới dùng availability guard và có fallback thật cho iOS 15.7.
- API camera, khóa và ký cài phải được thử trên máy thật; simulator không thay thế bằng chứng.
- Secrets, chứng chỉ, provisioning profile, UDID và Apple ID không được đưa vào repo/gói gửi review.

## Review Focus

1. Camera ngừng gửi mẫu hoặc tác vụ Vision hoàn thành muộn: không tiếp tục cộng “có mặt”; kiểm tra Task 2 và 5.
2. Tick trễ, đổi ngày giờ, sự kiện trùng hoặc tới sai thứ tự: tổng thời gian không âm, không cộng đôi, không kéo dài hạn; kiểm tra Task 2 và 6.
3. Kill app, khởi động lại, file lỗi hoặc lưu thất bại: không giả phục hồi phiên đang học, không khóa lại tự động; kiểm tra Task 3, 6 và 9.
4. Người dùng thoát Guided Access, app mất hoạt động hoặc camera bị thu hồi: ghi đúng loại gián đoạn, không kết luận đã mở TikTok; kiểm tra Task 4, 6 và 9.
5. Cúi viết, thiếu sáng, camera nóng, crop/mirror/orientation: không dùng “không thấy mặt” để tự kết luận bỏ học; kiểm tra Task 5 và 9.

---

## 1. Đặc tả iOS được triển khai

### 1.1. Phạm vi và lựa chọn công nghệ
Yêu cầu mới nhất của chủ sản phẩm: làm bản iOS trước để giao Antigravity; hỗ trợ từ **iOS 15.7**, giao diện và chức năng không bị thiết kế chỉ cho điện thoại cũ. Kế hoạch đa nền tảng trước đây vẫn là hướng dài hạn, nhưng Swift native là đề xuất kỹ thuật mới cho bản iOS độc lập này.

Không xây Flutter, Android, web app hoặc PWA trong đợt này. Không làm một trang demo rồi gọi là app iOS. iPhone là thiết bị chính; iPad native và đa cửa sổ để giai đoạn sau.

### 1.2. Các chế độ và mức bảo vệ
| Chế độ | Điều kiện | Thực hiện |
|---|---|---|
| Học nghiêm + camera | iOS 15.7+, camera được cấp quyền và hiệu chỉnh đạt, Guided Access đang bật | Bản chính; chỉ app và đồng hồ, xác nhận hiện diện |
| Học nghiêm không camera | iOS 15.7+, Guided Access đang bật | Bản chính; đồng hồ và báo cáo “không xác minh hiện diện” |
| Thử giao diện | Không cần Guided Access; debug/test hoặc màn hình dùng thử riêng | Không gọi là phiên khóa, không ghi thành tích học nghiêm |
| Managed Single App | Máy supervised và app được allowlist phù hợp qua quản lý thiết bị | Nhánh sau; chỉ bật khi Task 11 vượt kiểm chứng |
| Screen Time cá nhân | iOS 16+, entitlement/provisioning phù hợp | Nhánh tương lai; không cần cho bản chính, không được gọi là khóa toàn bộ máy |

Bản chính không phụ thuộc Family Controls hoặc tài khoản Developer trả phí để **viết và test logic**, nhưng cài lên máy vẫn phụ thuộc chữ ký phù hợp. Trong Guided Access, người dùng biết mã hệ thống vẫn có thể thoát. Đây là tự cam kết học, không phải cơ chế chống chủ sở hữu thiết bị.

### 1.3. Luồng sử dụng
Thiết lập an toàn → chọn thời lượng/chế độ → xin quyền camera nếu chọn → hiệu chỉnh vị trí → màn hình chờ khóa → người dùng bật Guided Access → app kiểm tra trạng thái thật → bấm bắt đầu → học → kết thúc → chỉ dẫn kết thúc Guided Access → tổng kết.

Hiệu chỉnh và hộp thoại quyền diễn ra **trước** khi tính giờ. Không ép người dùng bật camera. Không cho vào phiên học nghiêm khi Guided Access chưa bật. Khi người dùng bật khóa trước lúc hoàn tất preflight, app vẫn hiện nút quay lại/hướng dẫn thoát; không bắt đầu tự động.

### 1.4. Quy tắc thời gian
- Hạn kết thúc = thời điểm bắt đầu + thời lượng đã chọn, không gia hạn vì vắng, cảnh báo hoặc lỗi.
- Đồng hồ giao diện chỉ đọc snapshot, không tự tăng bộ đếm.
- Lõi chia thời gian đã trôi qua thành 5 nhóm loại trừ nhau: `present`, `absent`, `unknown`, `unverified`, `ineligible`.
- `present`: phiên hợp lệ, app active, khóa còn bật, mẫu đủ mới và đã đạt hiện diện ổn định 5 giây.
- `absent`: camera có khung hình hợp lệ nhưng không phát hiện người trong vùng đã hiệu chỉnh.
- `unknown`: đang chờ ổn định, mẫu hết hạn, thiếu sáng, camera lỗi hoặc không kết luận được.
- `unverified`: người dùng chọn không camera, nhưng app active và khóa còn bật. Không gắn nhãn là thời gian được camera xác nhận.
- `ineligible`: phiên đang chạy nhưng app inactive/background. Cảnh báo hệ thống không được coi là mở app giải trí.
- Tổng 5 nhóm bằng thời gian đã trôi qua được hạch toán, sai số số thực không quá 0.01 giây; tất cả không âm và không vượt thời lượng phiên.
- Không cộng bù khoảng vắng/unknown khi quay lại; không hồi tố cộng thời gian trước khi mẫu tới.
- Vắng liên tục đạt 30 giây chỉ phát một cảnh báo cho lần vắng đó; đạt 60 giây ghi một sự kiện rời lâu. Mất quan sát chuyển unknown và ngắt chuỗi vắng, không suy diễn tiếp.
- Hiện diện lại đủ 5 giây mới cộng tiếp; 5 giây chờ nằm trong unknown.
- Cập nhật đồng hồ mỗi giây khi active; thời lượng lấy từ clock, không từ số lần tick.
- Mẫu tới muộn hơn 3 giây hoặc cũ hơn mẫu đã nhận bị bỏ; không dùng để sửa timeline quá khứ.
- Phiên mất Guided Access khi đang chạy kết thúc sớm với lý do `lockReleased`; không tự khóa lại hoặc nối tiếp âm thầm.
- Mất active nhưng còn Guided Access: ngừng xác minh, đồng hồ hạn vẫn tiến. Khi active trở lại kiểm tra hạn/khóa trước, rồi chạy camera và chờ ổn định lại.
- Khi process bị kill/crash/reboot: lần mở sau đánh dấu phiên chưa kết thúc là interrupted tại checkpoint cuối đã lưu; không tiếp tục phiên cũ, không cộng thời gian app chưa quan sát, không so clock liên-process để đoán.
- Nếu crash làm mất tối đa 5 giây chưa checkpoint, báo báo cáo là dữ liệu tới checkpoint, không bịa độ chính xác.

### 1.5. Hiện diện và camera
Thiết bị đặt cố định nhìn thấy người học. Trước phiên cần kiểm tra ngồi thẳng, cúi viết và rời chỗ. Camera chỉ xác nhận có người trong vùng, không xác nhận đang học và không chống được mọi kiểu giả mạo.

Phân tích 2 khung/giây ở trạng thái bình thường; 1 khung/giây khi thermal serious; dừng xác minh khi critical. Capture có thể chạy ở tốc độ camera hỗ trợ cao hơn, nhưng pipeline chỉ giữ tối đa một frame đang xử lý và bỏ frame trễ. Không khẳng định camera chỉ tiêu thụ điện tương đương 2 FPS.

Dùng Vision human rectangles upper-body trước, có thể dùng face rectangles làm tín hiệu bổ sung khi human detector không thấy. Không dùng face ID hoặc embedding. Confidence khởi điểm 0.6; tâm bounding box nằm trong ROI người dùng hiệu chỉnh. Những giá trị này là tham số ban đầu cần đo, không phải bằng chứng chính xác 95%.

Khung hình quá tối theo ngưỡng luminance chuẩn hóa ban đầu 0.08, dữ liệu lỗi hoặc detector ném lỗi => unknown. Không có người trên khung hình có chất lượng hợp lệ => absent. Không tuyên bố phát hiện chắc chắn mọi trường hợp che camera.

Vùng ROI dùng tọa độ Vision chuẩn hóa; ánh xạ preview front camera có mirror bằng một utility có test. Bản đầu khóa orientation giao diện portrait trên iPhone; vẫn xử lý metadata orientation ảnh đúng. Không lưu ảnh hiệu chỉnh, chỉ ROI và thông số.

### 1.6. Thiết kế giao diện
Phong cách hiện đại, gọn: nền hệ thống, màu nhấn teal `#2A9D8F`, typography SF, khoảng cách nhất quán; tránh dựng “dashboard” nhiều biểu đồ trong phiên.

| Màn hình | Nội dung và hành vi |
|---|---|
| Welcome/Safety | Mục đích, giới hạn khóa, quyền riêng tư, cách thoát hệ thống |
| Home | Preset 25/50/90 phút, custom 2–180 phút, chọn camera, lịch sử |
| Calibration | Preview nhìn thấy rõ, vùng ROI, hướng dẫn cúi viết và bước rời chỗ |
| Preflight/Arm | Checklist quyền, camera, khóa thật, khả năng thoát; nút bắt đầu có điều kiện |
| Focus | Đồng hồ lớn, vòng tiến độ, trạng thái khóa/hiện diện dạng chữ + biểu tượng; nút trợ giúp/kết thúc sớm |
| Completion | Thời gian phiên, có mặt, vắng, không xác nhận, không camera, gián đoạn; nhắc kết thúc Guided Access |
| History/Settings | Lịch sử, xuất/xóa, thông số phiên sau, hướng dẫn khôi phục |

Không hiển thị preview khuôn mặt trong màn hình học mặc định. Không ẩn camera indicator hệ thống. Haptic nhẹ, animation ngắn, tắt hiệu ứng khi Reduce Motion. Kiểm tra cỡ chữ accessibility; không đặt số liệu quan trọng chỉ trong màu hoặc vòng tròn.

iOS mới có thể dùng `NavigationStack` từ iOS 16 trong wrapper, iOS 15.7 dùng navigation phù hợp; nội dung nghiệp vụ giống nhau. Không bắt buộc Liquid Glass, Live Activities, widget hoặc Apple Intelligence để app trông hiện đại.

### 1.7. Dữ liệu và ranh giới khôi phục
Lưu Application Support, JSON Codable version 1, atomic write, serial writer; không dùng UserDefaults cho log phiên. Session ID là UUID làm tên file; không dùng tên bài học ghép đường dẫn. Checkpoint mỗi 5 giây và mỗi chuyển trạng thái quan trọng.

Giữ sự kiện chi tiết 30 ngày dựa trên ngày trong record, không cần đọc timestamp filesystem. Giữ tổng kết tới khi người dùng xóa. Xuất CSV/JSON tổng hợp bằng share sheet ngoài phiên; không xuất clock hệ thống thô, credentials hoặc ảnh.

Bản iOS không có daemon/watchdog tùy ý chạy độc lập để tự gỡ Guided Access. Dừng đồng hồ của app không gỡ khóa hệ điều hành. Luôn giữ đường thoát do iOS cung cấp; không thu hoặc thay mã Guided Access trong app. Người dùng cần biết cách thoát trước khi bật khóa. Có thể nhờ người khác giữ mã, nhưng đó không phải thiết lập mặc định.

## 2. Chuẩn bị repo và cấu trúc file

Lưu kế hoạch này nguyên vẹn vào repo. Chủ đề tên sản phẩm: **Tâm Học**; target/scheme/module ASCII: `TamHoc`.

| Đường dẫn | Trách nhiệm |
|---|---|
| `TamHoc.xcodeproj/` | App, unit/UI test targets và shared scheme TamHoc |
| `Config/Debug.xcconfig`, `Config/Release.xcconfig` | Target 15.7, cấu hình build không chứa secrets |
| `TamHoc/App/TamHocApp.swift`, `AppEnvironment.swift` | Composition root và scene integration |
| `TamHoc/Session/SessionCoordinator.swift`, `SessionViewModel.swift` | Điều phối side effects; không tự tính thời gian |
| `TamHoc/Platform/SystemSessionClock.swift` | Clock monotonic + wall date |
| `TamHoc/Lock/GuidedAccessMonitor.swift` | Đọc trạng thái khóa và notification |
| `TamHoc/Presence/CameraPresenceMonitor.swift` | Quyền, capture queue, lifecycle camera |
| `TamHoc/Presence/VisionPersonDetector.swift` | Tạo observation từ pixel buffer |
| `TamHoc/Presence/PreviewGeometry.swift`, `Calibration.swift` | ROI, mirror/orientation và dữ liệu hiệu chỉnh |
| `TamHoc/Storage/FileSessionRepository.swift`, `AppSettings.swift` | Actor ghi file, settings và xử lý file lỗi |
| `TamHoc/Feedback/WarningPlayer.swift` | Âm thanh/haptic/VoiceOver khi nhận effect |
| `TamHoc/Export/SessionExporter.swift` | CSV/JSON, escaping và share sheet |
| `TamHoc/Features/{Onboarding,Home,Calibration,Preflight,Focus,History,Settings}/` | View/ViewModel từng tính năng, không view khổng lồ |
| `TamHoc/Design/Theme.swift`, `Components.swift` | Tokens và thành phần dùng chung |
| `TamHoc/Resources/Info.plist`, `PrivacyInfo.xcprivacy`, `Assets.xcassets`, `vi.lproj/Localizable.strings`, `reminder.wav` | Quyền, privacy, assets và bản dịch |
| `Packages/StudyCore/Package.swift` | Pure Swift package; iOS 15.7 qua app, package floor iOS 15/macOS 12 |
| `Packages/StudyCore/Sources/StudyCore/{Models,SessionEngine,TimelineLedger,PresencePolicy}.swift` | Domain, state machine và hạch toán |
| `Packages/StudyCore/Tests/StudyCoreTests/{TestSupport,SessionEngineTests,TimelineLedgerTests,PresencePolicyTests}.swift` | Tests với clock/mẫu giả |
| `TamHocTests/{Repository,GuidedAccess,Presence,Coordinator,Export,Availability}Tests.swift` | Unit/integration tests native |
| `TamHocTests/TestDoubles.swift` | Fake streams, clock, repository, sound |
| `TamHocUITests/{Onboarding,Preflight,Focus,Accessibility}Tests.swift` | UI tests có dependency injection |
| `scripts/verify.sh`, `scripts/archive.sh`, `scripts/package-review.sh` | Lệnh lặp lại được; lỗi phải trả exit code khác 0 |
| `docs/{BUILD,DEVICE_TESTS,RECOVERY,COMPATIBILITY,REVIEW_HANDOFF}.md` | Hướng dẫn và bằng chứng |
| `docs/superpowers/plans/2026-11-24-tamhoc-ios.md` | Kế hoạch này |

Chưa tạo `Managed`, `FamilyControls` hoặc extension target trong app mặc định. Chỉ thêm khi điều kiện nhánh tương ứng đã đạt. Không tạo các service placeholder trả success.

## 3. Hợp đồng dùng chung giữa các task

Các chữ ký dưới đây là quyết định thiết kế. Có thể thêm initializer/helper, nhưng không đổi tên hoặc nghĩa ở task sau mà không sửa toàn bộ nơi dùng và tests.

### Domain — trong Models.swift
- `TimePoint: Equatable`: `monotonicSeconds: Double`, `wallDate: Date`. Raw monotonic không lưu/export.
- `PresenceMode: String, Codable`: `cameraVerified`, `timerOnly`.
- `SessionConfiguration: Codable, Equatable`: `plannedSeconds: Double`, `presenceMode: PresenceMode`, `warningsEnabled: Bool`; `static func validated(plannedSeconds: Double, presenceMode: PresenceMode, warningsEnabled: Bool) throws -> Self`.
- `ObservationIssue: String, Codable`: `warmingUp`, `stale`, `lowLight`, `cameraUnavailable`, `thermal`, `detectorFailure`.
- `PresenceValue: Equatable`: `present`, `absent`, `unknown(ObservationIssue)`.
- `PresenceSample`: `sequence: UInt64`, `capturedMonotonicSeconds: Double`, `value: PresenceValue`.
- `ActivityState`: `active`, `inactive`, `background`.
- `EndReason: String, Codable`: `deadline`, `userEnded`, `lockReleased`, `processRestart`, `storageFailure`, `thermalLimit`, `clockFailure`.
- `SessionStatus: Codable, Equatable`: `running`, `completed`, `endedEarly(EndReason)`, `interrupted(EndReason)`.
- `TimeBucket: String, Codable`: `present`, `absent`, `unknown`, `unverified`, `ineligible`.
- `TimelineSegment: Codable`: `startElapsed: Double`, `endElapsed: Double`, `bucket: TimeBucket`.
- `SessionEventKind: String, Codable`: `sessionStarted`, `absenceWarning`, `longAbsence`, `presenceLost`, `presenceRecovered`, `activityChanged`, `cameraUnavailable`, `lockReleased`, `sessionEnded`, `storageFailure`.
- `SessionEvent: Codable`: UUID `id`, `elapsedSeconds: Double`, `kind: SessionEventKind`; không free-text chứa ảnh/token. Có thể thêm metadata dạng enum/string whitelist cho nguyên nhân, không ghi tên ứng dụng khác khi không có bằng chứng.
- `SessionRecord: Codable`: `schemaVersion = 1`, UUID `id`, `revision: UInt64`, `configuration`, `startedWallDate`, `status`, `elapsedSeconds`, `segments`, `events`. Tổng các bucket tính từ segments. Revision bắt đầu ở 0, tăng mỗi lần record thực sự thay đổi; event bị bỏ và terminal lặp không tăng revision.
- `SessionSnapshot`: `status`, `remainingSeconds`, `elapsedSeconds`, `secondsByBucket: [TimeBucket: Double]`, `presence: PresenceValue`.
- `SessionInput`: `tick`, `sample(PresenceSample)`, `activityChanged(ActivityState)`, `lockChanged(Bool)`, `finish(EndReason)`.
- `SessionEffect`: `warnAbsence`, `longAbsence`, `checkpoint`, `finish(EndReason)`.
- `SessionUpdate`: `snapshot: SessionSnapshot`, `effects: [SessionEffect]`.
- `SessionEngine`: `init(id: UUID, configuration: SessionConfiguration, startedAt: TimePoint)`; `mutating func handle(_ input: SessionInput, at time: TimePoint) throws -> SessionUpdate`; `var record: SessionRecord { get }`.
- `EngineError`: `invalidDuration`, `nonMonotonicTime`, `invalidSample`. NaN/Infinity bị từ chối; terminal không thay đổi lại, không phát finish lần hai.

### Adapter và coordinator
- `protocol SessionClock { func now() -> TimePoint }`.
- `@MainActor protocol GuidedAccessMonitoring: AnyObject { var isEnabled: Bool { get }; var changes: AsyncStream<Bool> { get } }`.
- `Calibration: Codable`: ROI x/y/width/height dạng Double trong [0,1], `schemaVersion = 1`; initializer ném lỗi nếu ROI rỗng/ngoài biên hoặc NaN.
- `PresenceMonitorEvent`: `generation: UUID`, `sample: PresenceSample`.
- `@MainActor protocol PresenceMonitoring: AnyObject { var events: AsyncStream<PresenceMonitorEvent> { get }; func start(calibration: Calibration, generation: UUID) async throws; func stop() async }`.
- `@MainActor protocol WarningPlaying { func playWarning() }`.
- `RepositoryReadResult`: `records: [SessionRecord]`, `quarantinedIDs: [UUID]`.
- `protocol SessionRepository: Sendable { func loadAll() async throws -> RepositoryReadResult; func save(_ record: SessionRecord) async throws; func delete(id: UUID) async throws }`.
- `FileSessionRepository` là actor implement SessionRepository. `actor SettingsRepository(directory: URL)` cung cấp `loadSettings() async throws -> AppSettings`, `saveSettings(_ settings: AppSettings) async throws`, `loadCalibration() async throws -> Calibration?`, `saveCalibration(_ calibration: Calibration) async throws`. Dữ liệu nằm trong settings.json và calibration.json, ghi atomic; file chưa có trả mặc định/ nil, file lỗi báo lỗi và giữ nguyên. Không đưa UIKit/Vision vào StudyCore.
- `@MainActor final class SessionCoordinator`: initializer nhận clock, lockMonitor, presenceMonitor, repository, warningPlayer; `func start(configuration: SessionConfiguration, calibration: Calibration?) async throws`; `func receiveActivity(_ state: ActivityState)`; `func endEarly() async`; `func recoverUnfinishedSessions() async throws`; publish `snapshot: SessionSnapshot?` và lỗi/ trạng thái khôi phục cho UI.
- Chỉ coordinator là chủ duy nhất được mutate engine. Camera queue gửi dữ liệu giá trị qua stream, không truyền CVPixelBuffer vào MainActor.

### Thứ tự và đồng thời
Coordinator đóng dấu `clock.now()` khi nhận event; sample vẫn giữ capture time để kiểm tra tuổi, nhưng hiệu lực bắt đầu tại lúc nhận, không sửa quá khứ. Event generation cũ bị bỏ ngay. Async save có thể reenter actor: ghi có revision tăng dần hoặc tuần tự hóa ở coordinator/repository để snapshot cũ không ghi đè terminal.

Trước khi await mở camera, tạo generation mới. Nếu người dùng hủy/thoát trong await, khi start trả về phải kiểm tra generation/status rồi stop tài nguyên tương ứng, không hồi sinh phiên.

## 4. Lệnh kiểm chứng chuẩn

Chạy trên macOS với Xcode, từ gốc repo; ghi version thật vào BUILD.md. Không tự nâng/cài toolchain trả phí. Nếu chỉ có Windows, vẫn viết mã/test source nhưng đánh dấu build iOS là **NOT RUN — requires macOS/Xcode**, không bịa kết quả.

```bash
xcodebuild -version
xcrun swift --version
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -showdestinations
swift test --package-path Packages/StudyCore
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Sau khi chọn simulator thực có trong danh sách, đặt `TAMHOC_SIMULATOR_ID` bằng UDID simulator đó:

```bash
xcodebuild -project TamHoc.xcodeproj -scheme TamHoc -destination "platform=iOS Simulator,id=$TAMHOC_SIMULATOR_ID" -resultBundlePath artifacts/Tests.xcresult test
```

Expected: `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`, mọi XCTest liên quan pass. Không dùng `|| true` hay pipeline che exit status. Lệnh không ký chỉ chứng minh compile, không tạo IPA cài được.

**Toolchain quan trọng:** deployment target, simulator support và device debugging support khác nhau. Tài liệu Apple hiện có các bản Xcode vẫn build target iOS 15 nhưng không còn debug thiết bị iOS 15. Chặng 0 phải chọn và ghi toolchain có hỗ trợ test thiết bị 15.7 thực; có thể dùng hai toolchain/runner đã ghi rõ cho máy cũ và iOS mới. Không sửa target lên 17 để “fix” việc Xcode mới không nhận máy. [S1]

## 5. Nhiệm vụ triển khai

### Task 1 — Nền dự án và chứng minh Guided Access trên thiết bị
**Files:** tạo project/config/composition root, `GuidedAccessMonitor.swift` bản probe tối thiểu, `TamHocTests/AvailabilityTests.swift`, BUILD.md, COMPATIBILITY.md, RECOVERY.md, DEVICE_TESTS.md. Tạo skeleton StudyCore với Models.swift để build. Không dựng toàn bộ UI trước.

**Interfaces:** consumes các hợp đồng ở mục 3; produces shared scheme `TamHoc`, product `TamHoc.app`, package StudyCore có test target, monitor đọc trạng thái thật.

- [ ] Viết `testDeploymentFloorIs157` kiểm tra metadata runtime app không yêu cầu iOS mới hơn 15.7; thêm build-setting check target app và tests dùng 15.7.
- [ ] Chạy check trước khi chỉnh config, ghi failure khi floor sai; đặt `IPHONEOS_DEPLOYMENT_TARGET = 15.7`, `SWIFT_VERSION = 5.0`, target device iPhone, app name Tâm Học.
- [ ] Chỉ thêm quyền camera với copy: “Tâm Học dùng camera để xác nhận bạn còn ở vị trí học. Hình ảnh được xử lý trên thiết bị, không được lưu hoặc gửi đi.” Không thêm quyền microphone/Photos/location hoặc background camera.
- [ ] Ghi toolchain/SDK/device-support thực tế; chạy build simulator và unsigned device build. Expected cả hai build succeed; chưa có Mac thì ghi BLOCKED tại bằng chứng, không đánh dấu đã build.
- [ ] Trên máy thử: bật Guided Access theo giao diện hệ thống, đọc trạng thái, thử Home/App Switcher rồi thoát bằng cơ chế iOS. Thử phiên 2 phút trước; không cấu hình MDM.
- [ ] Ghi riêng: vào khóa, ra khóa, hết thời gian trong app, crash app, reboot và khả năng thoát không mất dữ liệu. Không suy ra tự mở khóa vì app hiện “hoàn thành”.
- [ ] Commit `chore: establish iOS 15.7 app and guided access feasibility`.

**Gate:** thiếu máy thật không chặn viết các task logic, nhưng trạng thái khóa vẫn là **UNVERIFIED**; không phát hành “đã khóa nghiêm” khi chỉ test bằng mock.

### Task 2 — Lõi phiên học, ledger và presence policy
**Files:** tạo các file StudyCore và 4 file tests trong mục 2.

**Interfaces:** produces toàn bộ domain ở mục 3 và `SessionEngine.handle(_:at:)`. Internal `TimelineLedger` hợp nhất segment kề nhau cùng bucket; `PresencePolicy` quản lý ổn định 5 giây/cảnh báo 30/60 giây.

- [ ] Viết failing tests cho duration 119/10801/NaN bị từ chối; 120/3000/10800 hợp lệ; tên test `testDurationBounds`.
- [ ] Viết `testDelayedTickUsesClockAndClampsAtDeadline`: phiên 120 giây, tick từ t0 tới t200 => elapsed 120, remaining 0, completed, chỉ một finish.
- [ ] Viết `testStablePresenceRequiresFiveSeconds`: .present đều từ t0 tới t4 => present 0; tới t5 mới eligible, không cộng bù 5 giây đầu.
- [ ] Viết `testStaleSampleCannotAccruePresence`: sau khi đã stable, mẫu cuối tại t10, tick t20 => không có present sau t13; phần còn lại unknown.
- [ ] Viết `testAbsenceThresholdsOnce`: mẫu absent hợp lệ đều liên tục; 29.9 giây không warning, 30 có 1 warning, 60 có 1 longAbsence; tick tiếp không lặp; return stable rồi vắng lần mới có cảnh báo mới.
- [ ] Viết `testCameraGapBreaksAbsenceChain`: absent 20 giây rồi stale 20 giây => không suy thành vắng liên tục 40 giây.
- [ ] Viết `testInactiveIsIneligibleAndLockReleaseEndsEarly`, `testTimerOnlyNeverClaimsCameraVerified`, `testWallClockJumpDoesNotChangeDuration`, `testReorderedAndDuplicateSamplesIgnored`, `testAllBucketsPartitionElapsed`.
- [ ] Chạy `swift test --package-path Packages/StudyCore`; expected FAIL vì API chưa có hoặc assertions chưa đạt; không cố ý phá test đã pass.
- [ ] Implement các chữ ký mục 3. Mỗi event đóng ledger tới now, chia tại thời điểm sample hết hạn/deadline nếu nằm giữa; sau đó mới đổi trạng thái. Từ chối monotonic lùi/NaN. Mẫu invalid không gia hạn TTL. Không phát cảnh báo absent sau khi đã chuyển unknown.
- [ ] Chạy lại package tests; expected PASS. Thêm test chuỗi 10.000 event giả định để chứng minh không âm/không cộng trùng; seed cố định, không property-testing dependency.
- [ ] Commit `feat: implement deterministic study session engine`.

Ví dụ assertion cốt lõi, dùng fixture `makeEngine(duration:presenceMode:)` và `point(_ seconds: Double)` định nghĩa trong TestSupport.swift:
```swift
var engine = makeEngine(duration: 120, presenceMode: .timerOnly)
let result = try engine.handle(.tick, at: point(200))
XCTAssertEqual(result.snapshot.elapsedSeconds, 120, accuracy: 0.01)
XCTAssertEqual(result.snapshot.remainingSeconds, 0, accuracy: 0.01)
XCTAssertEqual(result.snapshot.status, .completed)
```
Fixture engine bắt đầu tại point(0), app active, khóa enabled; preflight thật do coordinator bảo đảm ở Task 6.

### Task 3 — Persistence, checkpoint và phục hồi phiên dang dở
**Files:** FileSessionRepository.swift, AppSettings.swift, RepositoryTests.swift; bổ sung `TamHoc/Storage/SettingsRepository.swift`, `TamHoc/Storage/SessionRecovery.swift` và `RepositoryReadResult` ở module app.

**Interfaces:** consumes SessionRecord; produces actor `FileSessionRepository(directory: URL)`, `SessionRecovery.interruptUnfinished(_ record: SessionRecord) -> SessionRecord`, `AppSettings` chứa defaultDurationSeconds, defaultPresenceMode, warningsEnabled, onboardingVersionSeen.

- [ ] Viết `testAtomicRoundTrip`, `testCorruptRecordIsQuarantinedWithoutDeletingHistory`, `testUnsupportedSchemaIsPreserved`, `testRunningRecordBecomesInterruptedAtCheckpoint`, `testOlderRevisionCannotOverwriteTerminal`, `testDiskWriteFailureIsReported`.
- [ ] Assertions bắt buộc: record đang running lưu elapsed 100, mở lại => interrupted(processRestart), elapsed vẫn 100, không cộng thời gian wall; file hỏng không làm mất file phiên tốt; schema tương lai không bị tự ghi đè.
- [ ] Chạy unit tests chọn `TamHocTests/RepositoryTests`; expected FAIL trước implementation.
- [ ] Implement JSON schema 1, tên file UUID, ghi atomic và data protection phù hợp iOS. Trong actor, revision thấp hơn bản đã lưu là no-op, cùng revision và cùng dữ liệu là idempotent, cùng revision nhưng khác dữ liệu báo revisionConflict và giữ bản cũ. Khi mở file, khởi tạo revision guard từ dữ liệu hiện có; recovery tăng revision trước khi ghi. Không đưa raw monotonic vào JSON.
- [ ] Implement SettingsRepository và test round-trip settings/ROI, default khi thiếu file, không tự reset settings khi file decode lỗi. Các cài đặt người dùng không được silently đổi chế độ phiên đang chạy.
- [ ] Khi decode hỏng, chuyển file vào thư mục quarantine của app, không xóa; nếu quarantine cũng thất bại, trả lỗi rõ. Unknown schema được giữ nguyên/read-only và báo không hỗ trợ.
- [ ] Chạy lại tests; expected PASS. Xem thử trong app container không có ảnh/video hoặc khóa bí mật.
- [ ] Commit `feat: persist sessions and recover interrupted runs`.

**Lưu ý:** không “xử lý disk full” bằng xóa dữ liệu người dùng. Dừng phiên mới nếu initial save thất bại; mid-session failure kết thúc sớm và hiện rằng kết quả có thể chưa lưu.

### Task 4 — Guided Access và vòng đời thực tế
**Files:** hoàn thiện GuidedAccessMonitor.swift; tạo `TamHoc/Platform/AppActivityMonitor.swift`, GuidedAccessTests.swift và TestDoubles.swift.

**Interfaces:** produces GuidedAccessMonitoring; `AppActivityMonitor` chuyển lifecycle UIKit/scene thành ActivityState, một nguồn sự kiện duy nhất sau khi khử trùng.

- [ ] Viết `testMonitorReadsInitialSystemStatus`, `testStatusNotificationRereadsBoolean`, `testDuplicateLifecycleEventsAreCoalesced`, `testUnknownDestinationIsNotLabeledTikTok`.
- [ ] Chạy test bằng source trạng thái injected; expected FAIL trước implementation.
- [ ] Đọc `UIAccessibility.isGuidedAccessEnabled`; nghe `UIAccessibility.guidedAccessStatusDidChangeNotification`. Notification là tín hiệu để đọc lại trạng thái, không tự toggle biến.
- [ ] Implement events stream và hủy observer đúng lifetime. Xử lý scene active/inactive/background; nếu dùng cả scenePhase và notifications phải coalesce.
- [ ] Không gọi `requestGuidedAccessSession` để “bật” ở bản unmanaged; không gọi Settings private URL, không truy tìm tên process app khác.
- [ ] Chạy lại tests, rồi xác minh thay đổi trạng thái trên máy thật và ghi kết quả; simulator chỉ xác minh logic injected.
- [ ] Commit `feat: observe guided access and app activity honestly`.

### Task 5 — Camera, Vision, ROI và hiệu chỉnh
**Files:** CameraPresenceMonitor.swift, VisionPersonDetector.swift, PreviewGeometry.swift, Calibration.swift, PresenceTests.swift; view Calibration ở mức dùng thử.

**Interfaces:** consumes SessionClock và Calibration; produces PresenceMonitoring; `VisionPersonDetector.detect(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, calibration: Calibration) throws -> PresenceValue`; `PreviewGeometry.visionROI(fromPreviewRect: CGRect, previewBounds: CGRect, imageSize: CGSize, mirrored: Bool) throws -> Calibration` cho portrait preview aspect-fill.

- [ ] Viết `testROIMirrorAndAspectFillMapping` với center ROI, left/right mirror, crop ngoài biên và ROI NaN; `testSampleThrottleAndSingleInflightFrame`; `testPermissionDeniedDoesNotStartCapture`; `testStoppedGenerationNeverPublishesNewSamples`; `testLowLightAndDetectorFailureProduceUnknown`.
- [ ] Chạy tests với fake detector/capture source; expected FAIL trước implementation. Synthetic detector tests chỉ kiểm tra mapping/quy tắc, không khẳng định Vision nhận người chính xác.
- [ ] Implement xin camera khi người dùng chọn chế độ camera; không hỏi khi mở app lần đầu nếu chưa cần. Chọn front camera mặc định; nếu không có => chế độ camera unavailable, vẫn có timer-only.
- [ ] Session capture chạy serial queue riêng, không `startRunning()` trên main thread. `alwaysDiscardsLateVideoFrames = true`; hạn chế sample 2 Hz bằng capture timestamp, không queue nhiều frame. Dùng pixel format native phù hợp; không convert mọi frame sang UIImage/JPEG.
- [ ] Vision request tương thích 15.7; human upper-body, face bổ sung; ngưỡng 0.6 và ROI theo spec. Capture-time từ cùng clock inject với engine; sequence tăng trong generation.
- [ ] Implement permission denied/restricted, runtime error, interruption, orientation/mirror và thermal. Unknown event phải được gửi khi camera mất khả năng quan sát; không giữ present cũ.
- [ ] Calibration có bước 5 giây ngồi, 5 giây cúi viết, 5 giây rời chỗ. Nếu không phân biệt được ba đoạn, không cho chế độ camera nghiêm bắt đầu; cho chỉnh góc hoặc chọn timer-only. Không lưu frame để test sau.
- [ ] Chạy tests; trên máy thật thử đủ tư thế và ghi confusion counts. Capture permission/camera không được đánh dấu PASS chỉ vì fake stream pass.
- [ ] Commit `feat: add on-device presence calibration and camera pipeline`.

### Task 6 — Coordinator tích hợp không race, không cộng sai
**Files:** SessionCoordinator.swift, SessionViewModel.swift, SystemSessionClock.swift, AppEnvironment.swift, CoordinatorTests.swift; bổ sung `Resources/PrivacyInfo.xcprivacy`.

**Interfaces:** consumes contracts Task 2–5; produces SessionCoordinator ở mục 3. Clock implementation dùng continuous monotonic có tính thời gian sleep, ví dụ `mach_continuous_time` với timebase được kiểm chứng; clock failure chuyển endReason clockFailure.

- [ ] Viết `testStartRequiresRealLock`, `testCameraModeRequiresValidCalibration`, `testInitialSaveFailurePreventsRunning`, `testLockLossEndsOnlyOnce`, `testInactiveStopsPresenceButDeadlineAdvances`, `testCancelWhileCameraStartAwaitingDoesNotResurrectSession`, `testLateOldGenerationIsIgnored`, `testSlowSaveCannotOverwriteCompletion`.
- [ ] Assertions: không lock => không engine running; generation cũ không thay snapshot; phát 2 lock-loss chỉ 1 terminal; camera-start đang await rồi endEarly => trở lại không camera/không running.
- [ ] Chạy tests; expected FAIL trước implementation.
- [ ] Implement @MainActor coordinator, một task tick active 1 Hz, một consumer lock changes, một consumer presence; cancel tasks theo lifetime. Snapshot từ engine là nguồn dữ liệu duy nhất.
- [ ] Preflight camera xong mới arm/start; reread khóa ngay trước start. Lưu initial record thành công rồi mới công bố running; kiểm tra lại generation/khóa sau từng await. Nếu stale trong lúc setup, hủy start và không đếm giờ.
- [ ] Khi inactive/background: đóng ledger, yêu cầu stop camera, checkpoint chuyển trạng thái; dùng background task hữu hạn nếu cần hoàn tất save, không cố chạy timer/camera nền.
- [ ] Khi active: tick với clock hiện tại trước khi khởi động lại camera; nếu đã deadline thì hoàn thành ngay. Không backfill hiện diện khi app ngủ.
- [ ] Checkpoint 5 giây; endEarly/deadline/lockReleased idempotent; stop camera, khôi phục idle-timer policy thuộc app, lưu cuối; nếu save thất bại hiển thị lỗi thay vì “đã lưu”.
- [ ] Audit required-reason APIs; privacy manifest khai `NSPrivacyAccessedAPICategorySystemBootTime` reason `35F9.1` nếu dùng API thuộc nhóm để đo thời lượng trong app. Không xuất clock thô; kiểm tra lại danh mục Apple cho API thực dùng. Không thêm lý do/thu thập dữ liệu không có trong code. [S8]
- [ ] Chạy package + coordinator tests; expected PASS, Thread Sanitizer trên simulator khi khả dụng không báo race trong adapter.
- [ ] Commit `feat: coordinate reliable locked study sessions`.

### Task 7 — UI sản phẩm hiện đại, tối giản và truy cập được
**Files:** các Features và Design ở mục 2; Assets, localizations; Onboarding/Preflight/Focus/Accessibility UI tests.

**Interfaces:** consumes SessionViewModel/Coordinator, không gọi camera hay Guided Access trực tiếp trong View; produces UI flow mục 1.3 và các accessibilityIdentifier ổn định: `home.duration`, `home.cameraToggle`, `preflight.lockStatus`, `preflight.start`, `focus.remaining`, `focus.presence`, `focus.help`, `focus.endEarly`, `summary.status`.

- [ ] Viết UI tests `testCannotStartWithoutGuidedAccess`, `testCameraDeniedOffersTimerOnly`, `testTimerOnlySummaryIsNotVerified`, `testCompletionStillExplainsGuidedAccessExit`, `testLargeTextKeepsHelpReachable`.
- [ ] UI tests inject fake adapters qua launch arguments chỉ ở Debug/test build. Release không có đường ép lock=true. Viết check Release không chứa bypass runtime flag.
- [ ] Chạy UI tests; expected FAIL vì flow chưa có.
- [ ] Implement Welcome, Home, Calibration, Preflight, Focus, Completion, History và Settings theo spec. Không phải chỉ vài màn hình static.
- [ ] Focus: countdown SF monospaced, ring cập nhật từ thời gian, đủ contrast; chữ “Có mặt”, “Đang chờ ổn định”, “Không thể xác nhận”, “Không dùng camera”. Không chỉ đổi màu.
- [ ] Help luôn có hướng dẫn kết thúc bằng iOS. Nút kết thúc sớm xác nhận rõ rằng app dừng phiên nhưng Guided Access có thể vẫn bật; sau đó mở màn hình khôi phục thay vì báo đã mở khóa.
- [ ] `UIApplication.isIdleTimerDisabled` chỉ đổi trong lúc cần app active; ghi/khôi phục trạng thái trước đó khi rời luồng. Không tự đổi độ sáng hệ thống hoặc âm lượng.
- [ ] Dùng availability wrappers cho API mới. Test iPhone màn hình nhỏ, màn hình lớn, notch/Dynamic Island, Light/Dark, Reduce Motion, Dynamic Type accessibility; tối thiểu 44pt vùng chạm và VoiceOver label.
- [ ] Chạy UI tests + accessibility audit thủ công trên iOS15.7 và iOS mới sẵn có; không dùng compiler availability suppressions để né runtime crash.
- [ ] Commit `feat: deliver accessible modern iPhone study flow`.

### Task 8 — Cảnh báo, lịch sử, retention và xuất dữ liệu
**Files:** WarningPlayer.swift, reminder.wav, SessionExporter.swift, History/Settings, ExportTests.swift; bổ sung `RetentionPolicy.swift` và test.

**Interfaces:** produces WarningPlaying và `SessionExporter.csv(records: [SessionRecord]) -> Data`, `SessionExporter.json(records: [SessionRecord]) throws -> Data`; `RetentionPolicy.pruneDetailedEvents(in record: SessionRecord, now: Date) -> SessionRecord`.

- [ ] Viết `testWarningOncePerAbsence` ở integration level; `testCSVQuotesNewlinesAndFormulaPrefixes`; `testExportContainsNoRawClockOrImage`; `testRetentionKeepsSummaryAfter30Days`; `testHistoryDeletionPersists`.
- [ ] CSV quy định UTF-8, header cố định; escape dấu ngoặc kép/newline; text có prefix =,+,-,@ được trung hòa khi mở spreadsheet; không thay dữ liệu số thành text tùy tiện.
- [ ] Chạy tests; expected FAIL trước implementation.
- [ ] Implement âm báo ngắn tự tạo/có quyền dùng, AVAudioSession ambient, không ép vượt silent mode/âm lượng; haptic/VoiceOver theo cài đặt. Không xin microphone hoặc push notification chỉ để nhắc trong foreground.
- [ ] Export tổng hợp chỉ ngoài phiên bằng share sheet, không tự gửi mạng. Retention bỏ events chi tiết cũ hơn 30 ngày nhưng giữ segments đã tổng hợp/totals phục vụ lịch sử; tránh lưu tọa độ hoặc chi tiết người quan sát trong event.
- [ ] Retention dùng ngày trong record, clock wall lùi không được làm xóa nhầm hàng loạt; chỉ prune record có ngày hợp lệ và older-than cutoff. Ghi file atomic như Task 3.
- [ ] Chạy tests, kiểm tra file export bằng trình đọc CSV và JSON parser; expected PASS.
- [ ] Commit `feat: add private session history and exports`.

### Task 9 — Kiểm chứng thiết bị thật và hardening
**Files:** DEVICE_TESTS.md, RECOVERY.md, COMPATIBILITY.md; bổ sung tests ở module sở hữu lỗi tìm được.

**Interfaces:** consumes bản app thật; produces ma trận có kết quả `PASS / FAIL / NOT RUN`, model/OS/build commit và ngày thử, không có secrets.

- [ ] Chạy toàn bộ package, native unit và UI tests; ghi lệnh/exit code/xcresult.
- [ ] Thử ít nhất một iPhone đang iOS 15.7.x và một iPhone iOS mới hơn; thêm small-screen và large-screen bằng simulator. Nếu thiếu 15.7 thật, không ghi đã chứng nhận mọi máy15.7+, giữ đó là release gate chưa đạt.
- [ ] Guided Access: setup bình thường, sai mã, hết giờ app, thoát giữa phiên, crash, reboot, mở lại. Lưu thao tác thực tế cho đúng phiên bản iOS; không copy cứng số lần bấm từ tài liệu phiên bản khác.
- [ ] Camera: denied, revoked, missing hardware ở fake, thiếu sáng, cúi viết, người khác đi qua, che ống kính, app inactive do hộp thoại, thermal warning, khóa màn hình. Với iOS không cho mô phỏng nhiệt thật an toàn, dùng injected thermal event và ghi rõ loại bằng chứng.
- [ ] Độ chính xác mục tiêu: ít nhất 20 lần rời bàn trên 60 giây sau hiệu chỉnh; phát hiện ít nhất 19/20 trong độ trễ xử lý tối đa 3 giây sau ngưỡng. Quan sát 2 giờ học giấy để đếm false alarms, mục tiêu không quá 1. Nếu không đạt, sửa hoặc ghi camera experimental; không quảng cáo đã đạt.
- [ ] Đo phiên 50 phút trên thiết bị cũ và mới: pin đầu/cuối, điều kiện sạc, nhiệt hệ thống, peak memory bằng Instruments, UI responsiveness. Mục tiêu ban đầu peak memory <150MB và không thermal serious kéo dài do app; ghi số đo thật, không “ước tính” thành kết quả.
- [ ] Nếu thermal serious giảm phân tích còn1Hz; critical gửi unknown, kết thúc sớm thermalLimit, giải phóng capture, hiện đường thoát. Không dùng vòng lặp cố chống iOS ngắt camera.
- [ ] Disk full/corrupt/unsupported schema, kill trong lúc save, đổi giờ ±24h, callback trễ và callback lặp: chạy automated tests rồi thử những ca an toàn trên máy phụ.
- [ ] Kiểm tra thu hồi quyền/không mạng không khiến app tự mở Settings bằng cách riêng hoặc giữ người dùng mắc kẹt.
- [ ] Mọi lỗi sửa phải có regression test phù hợp, rồi chỉ chạy lại checks liên quan + suite phát hành; commit `fix: harden lifecycle presence and recovery`.

### Task 10 — Build, ký IPA, cài 3uTools và gói review
**Files:** scripts/verify.sh, archive.sh, package-review.sh; BUILD.md, REVIEW_HANDOFF.md, `.gitignore`; export options template không có team secrets.

**Interfaces:** produces `TamHoc.xcodeproj` build được, signed IPA **nếu có provisioning hợp lệ**, gói source review và bằng chứng test.

- [ ] Viết verify.sh chạy package tests, native build/test với simulator đã chọn; shell `set -euo pipefail`. Kiểm tra minimum deployment, không chứa private API và không entitlement không dùng.
- [ ] Chạy script ở trạng thái còn lỗi để xác minh exit code khác0; sau khi hoàn tất app chạy expected exit0.
- [ ] archive.sh chỉ dùng macOS/Xcode; mặc định không tự login Apple ID, mua chứng chỉ hoặc sửa tài khoản. Bundle ID dùng reverse-DNS thuộc team của người dùng khi ký, giữ ổn định khi cập nhật.
- [ ] Compile-only không ký được ghi là unsigned artifact; tuyệt đối không đổi extension zip thành IPA rồi gọi là có thể cài.
- [ ] Nếu có team/profile hợp lệ: archive theo scheme, export bằng Development/Debugging hoặc Ad Hoc/Release Testing tương ứng phiên bản Xcode. Tạo ExportOptions.plist bằng Xcode của host rồi lưu template đã bỏ team ID; không copy mù tên method từ Xcode khác.
- [ ] Sau export, kiểm tra MinimumOSVersion=15.7, executable arm64, embedded profile, bundle ID, entitlements, hạn profile và UDID thiết bị được phép. Không in toàn bộ provisioning chứa UDID vào log review.
- [ ] Với Personal Team, ghi đúng giới hạn profile thường7 ngày và khả năng export thực tế; nếu Xcode không export IPA theo luồng đó, báo rõ chỉ test-install trực tiếp được, không hứa Ad Hoc miễn phí. Có thể thử ký lại bằng3uTools với quyền tài khoản phù hợp; cần xác minh trên máy thực, không xem ký thành công là đã chạy thành công. [S9–S11]
- [ ] Cài IPA đã ký qua chức năng import/install của3uTools; trust trong Settings khi iOS yêu cầu. Không chép mật khẩu Apple ID vào chat/script. Test mở app, camera, Guided Access, kết thúc và cập nhật cùng bundle ID có giữ lịch sử.
- [ ] Gói review gồm source, xcodeproj/shared scheme, configs, package, tests, scripts, tài liệu và plan; loại `DerivedData`, build intermediates, .p12/.p8, profiles, secrets, user-state Xcode và ảnh camera.
- [ ] REVIEW_HANDOFF.md ghi commit hash, lệnh đã chạy, số tests pass/fail, ma trận máy, hạn chế, cách tái hiện bug, trạng thái ký/cài; file test result dạng chia sẻ đã rà dữ liệu riêng tư. Nếu chưa có Mac/thiết bị/chữ ký, ghi NOT RUN/BLOCKED rõ.
- [ ] Commit `build: package reproducible iOS app and review handoff`.

**Không đưa lên App Store/TestFlight trong task này.** Không tính có file IPA là đủ khi chưa xác minh mở được trên iPhone.

### Task 11 — Nhánh tùy chọn: tự vào/ra Single App trên máy managed
**Không phải điều kiện để giao bản chính Task 1–10.** Người dùng chấp nhận máy chuyên dụng nhưng chưa đồng ý reset. Chỉ viết phần này khi có máy supervised phù hợp hoặc người dùng duyệt quy trình enrollment cụ thể sau khi thấy ảnh hưởng dữ liệu.

**Files, nếu đủ điều kiện:** `TamHoc/Managed/ManagedSingleAppController.swift`, `ManagedConfigurationReader.swift`, `TamHocTests/ManagedSingleAppTests.swift`, `docs/MANAGED_SETUP.md`; tách chế độ quản lý khỏi GuidedAccessMonitor thụ động.

**Interfaces:** `@MainActor protocol ManagedSingleAppControlling { func enter() async throws; func exit() async throws }`; lỗi `notEligible`, `requestRejected`, `timeout`, `recoveryUnverified`. Không có `return true` mặc định.

- [ ] Đọc yêu cầu supervised và app allowlist cho API `requestGuidedAccessSession(enabled:completionHandler:)`; viết thiết kế cấu hình MDM cụ thể và cách khôi phục tại chỗ. Không chỉ thêm entitlement tự nghĩ ra. [S3]
- [ ] Thử vào/ra trên máy phụ được quản lý sẵn. Ghi callback success/failure, trạng thái hệ thống và giới hạn quan sát. Không dùng sự hiện diện của managed configuration làm bằng chứng app chắc chắn đã được allowlist.
- [ ] Trước khi code vào bản phát hành, chứng minh app crash/kill/reboot/chữ ký hết hạn vẫn có đường thoát tại chỗ không mạng và không xóa dữ liệu. Nếu không có thì giữ nhánh experimental, không cho người dùng bật khóa nghiêm dài hạn.
- [ ] Viết failing tests `testDeniedEntryDoesNotStartTimer`, `testExitTimeoutDoesNotClaimUnlocked`, `testDeadlineRequestsExitOnce`, `testLateSuccessAfterCancelIsBalancedByExit`; implement callbacks timeout rõ ràng, generation và cặp enter/exit cân bằng.
- [ ] Hoàn thành phiên và gọi exit; chỉ hiển thị yêu cầu đã được hệ thống xác nhận theo tín hiệu có thật, không suy luận từ việc đã gửi lệnh MDM.
- [ ] Không tạo watchdog/daemon tùy ý để hứa chạy nền trên iOS. Nếu yêu cầu tự mở khóa khi app chết chưa đáp ứng được, ghi hạn chế và không ship chế độ đó.
- [ ] Commit riêng nhánh; không merge chỉ vì unit mock pass.

### Task 12 — Nhánh tương lai iOS16+: Screen Time
Đây là đường phát triển độc lập, **không implement trong bản đầu** và không thêm capability vào target chính để làm hỏng việc ký IPA đơn giản.

Nếu được đặt làm đợt tiếp: đọc FamilyControls/ManagedSettings/DeviceActivity, xin capability/provisioning cho app và extensions; dùng individual authorization từ iOS16; availability guard mọi entry; store có tên riêng và chỉ gỡ settings thuộc app; recovery/out-of-app expiry cần thử. Người dùng có thể thu hồi quyền nên không hứa không thể vượt qua. Chỉ xây sau một kế hoạch extension riêng, không nhét vào Task 10. [S12–S13]

## 6. Checklist nghiệm thu và phạm vi “đã xong”
| Hạng mục | Điều kiện |
|---|---|
| Source | Mở project và build được bằng lệnh ghi trong BUILD.md; không thiếu asset/package/project |
| Hệ điều hành | Deployment15.7 và mọi API mới có fallback; 15.7 thật còn thiếu thì ghi rõ chưa chứng nhận |
| Khóa | Guided Access thật, không full-screen giả; hiểu và thử đường thoát |
| Đồng hồ | Clock-driven, duration bounds, ledger tổng đúng, không cộng bù |
| Hiện diện | Mất mẫu => unknown; cúi viết/calibration được thử; số liệu accuracy ghi thật |
| Camera | Cấp quyền chủ động, stop khi background/terminal, không lưu ảnh/video |
| Giao diện | Tối giản nhưng hoàn chỉnh, Light/Dark, cỡ chữ lớn, VoiceOver |
| Lưu dữ liệu | Atomic/revision ordering, recovery từ checkpoint, không mất lịch sử khi file hỏng |
| Cài đặt | Signed IPA nếu có điều kiện; nếu chưa ký được báo thiếu gì, không tạo kết quả giả |
| Khôi phục | Crash/reboot/lock exit có biên bản trên máy thật; không tự reset |
| Bàn giao | Commit/source/tests/scripts/known issues đầy đủ, không bí mật hoặc dữ liệu riêng tư |

Nếu chỉ có simulator và mock, được giao bản developer preview kèm checklist còn thiếu; không tuyên bố đã nghiệm thu trên iPhone. Không cần đợi nhánh MDM/Screen Time mới bàn giao bản chính.

## 7. Prompt đưa cho Antigravity

Sao chép đoạn sau cùng với toàn bộ file kế hoạch này:

```text
Hãy triển khai Tâm Học cho iPhone theo kế hoạch đính kèm.
Yêu cầu mới nhất: iOS 15.7 trở lên, giao diện hiện đại, không thiết kế chỉ cho iPhone 7.

Đọc toàn bộ đặc tả và hợp đồng trong file trước. Lưu file vào
docs/superpowers/plans/2026-11-24-tamhoc-ios.md rồi làm Task 1–10 theo thứ tự.
Dùng Swift/SwiftUI native, package StudyCore, AVFoundation/Vision và Guided Access.
Không chuyển thành website/Flutter hoặc nâng minimum iOS để né lỗi.
Không chỉ dựng UI; phải có engine, adapter thật, persistence, tests và hướng dẫn cài.

Mỗi task: viết test có ý nghĩa trước, chạy thấy fail khi có phần chưa implement,
implement tối thiểu, chạy pass, commit. Cập nhật checklist và REVIEW_HANDOFF.md.
Không dùng mock trong Release để giả camera/khóa đang hoạt động.
Không giả tên app mà iOS không cung cấp, không fake kết quả build/test/IPA.
Nếu không có Mac, thiết bị thật hoặc chữ ký, vẫn hoàn thành phần không phụ thuộc
nhưng ghi NOT RUN/BLOCKED và giữ release gate; không đánh dấu đã cài được.

Không thực hiện reset/enrollment MDM, jailbreak/root, private API,
đăng App Store, mua dịch vụ hay đưa credentials vào repo.
Task 11 có điều kiện riêng; Task 12 ngoài scope bản đầu.
Giữ đường thoát Guided Access rõ ràng; hết giờ không được báo máy đã mở khóa
nếu app chỉ kết thúc phiên.

Cuối cùng giao source đầy đủ, project/shared scheme, tests, scripts, plan,
BUILD.md, DEVICE_TESTS.md, RECOVERY.md, COMPATIBILITY.md,
REVIEW_HANDOFF.md và IPA đã ký nếu thực sự xuất/cài được.
Tôi sẽ đưa source cho Codex review trước khi dùng lâu dài trên máy chính.
```

## 8. Gói gửi Codex review sau này
Gửi repo hoặc ZIP source có **toàn bộ** `.swift`, `.xcodeproj`, shared scheme, `.xcconfig`, Info.plist, PrivacyInfo.xcprivacy, assets cần build, Packages, tests, scripts và docs. Không chỉ gửi IPA hoặc ảnh giao diện.

Trong REVIEW_HANDOFF.md yêu cầu Antigravity điền:
- Commit/branch và phạm vi Task đã xong.
- macOS/Xcode/Swift/SDK và simulator đã dùng; model/iOS máy thật đã test.
- Lệnh và exit code, số tests, test nào skipped/NOT RUN.
- Trạng thái Guided Access, camera, sleep/background/reboot và cách thoát.
- Trạng thái ký/cài IPA; thiếu chứng chỉ/thiết bị thì ghi cụ thể, không gửi secret.
- Lỗi còn biết, phần dùng fake chỉ trong test và mọi thay đổi khác kế hoạch.
- Số liệu pin/nhiệt/accuracy thật và giới hạn thử.

Review sau sẽ ưu tiên: quyền khóa thật, thoát an toàn, accounting, callbacks/race,
camera không lưu/không chạy nền giả, khả dụng API15.7 và khả năng build lặp lại.
Kết quả sẽ phân loại lỗi chặn phát hành, lỗi đáng sửa và cải tiến;
review mã không thay thế thử nghiệm trên thiết bị.

## 9. Tự kiểm tra kế hoạch
Đã đối chiếu yêu cầu: iOS15.7+ (Task1/7/10), khóa (1/4/11),
timer/presence (2/5/6), privacy/storage (3/6/8),
UI (7), recovery/device evidence (9), IPA/review (10).
Năm Review Focus đều có test ở task sở hữu. Task11/12 có gate rõ,
không làm điều kiện mơ hồ cho việc hoàn thành bản chính.
Các default mới là đề xuất kỹ thuật, không phải số đo đã đạt.

## 10. Tài liệu chính thức đã kiểm tra
Tra cứu ngày24/11/2026; đọc lại API thực dùng khi triển khai, nhất là toolchain và signing.

- [S1 — Apple: Xcode, deployment target và device support](https://developer.apple.com/xcode/system-requirements/)
- [S2 — Apple: Guided Access, giới hạn thời gian và thao tác kết thúc](https://support.apple.com/111795)
- [S3 — Apple: requestGuidedAccessSession và yêu cầu MDM/supervised](https://developer.apple.com/documentation/uikit/uiaccessibility/requestguidedaccesssession(enabled:completionhandler:))
- [S4 — Apple: theo dõi trạng thái Guided Access](https://developer.apple.com/documentation/uikit/uiaccessibility/guidedaccessstatusdidchangenotification)
- [S5 — Apple: camera gián đoạn khi app ra nền](https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason/videodevicenotavailableinbackground)
- [S6 — Apple: quyền camera và usage description](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)
- [S7 — Apple: Vision human rectangles](https://developer.apple.com/documentation/vision/vndetecthumanrectanglesrequest)
- [S8 — Apple: required-reason APIs và privacy manifest](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [S9 — Apple: Personal Team và provisioning7 ngày](https://developer.apple.com/help/account/basics/about-your-developer-account/)
- [S10 — Apple: archive ngoài App Store](https://help.apple.com/xcode/mac/current/en.lproj/devf37a1db04.html)
- [S11 — 3uTools: ký và cài IPA](https://www.3u.com/tutorial/articles/12092/)
- [S12 — Apple: individual authorization từ iOS16](https://developer.apple.com/videos/play/wwdc2022/110336/)
- [S13 — Apple: entitlement Family Controls](https://developer.apple.com/documentation/xcode/configuring-family-controls)
- [S14 — Apple: frame output, drop frame trễ](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput)
- [S15 — Apple: continuous monotonic clock](https://developer.apple.com/documentation/kernel/1646199-mach_continuous_time)
