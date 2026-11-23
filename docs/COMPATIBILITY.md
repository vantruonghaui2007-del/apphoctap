# Tương thích Hệ điều hành & Thiết bị — Tâm Học

## Mục tiêu tương thích
- **Tối thiểu:** iOS `15.7` (`IPHONEOS_DEPLOYMENT_TARGET = 15.7`).
- **Thiết bị chính:** iPhone (`TARGETED_DEVICE_FAMILY = 1`), khóa hướng dọc (`UIInterfaceOrientationPortrait`) trong bản đầu.
- **Kiến trúc thiết bị:** `arm64`.

## Bảng sử dụng API và Fallback cho iOS 15.7
| Thành phần | API iOS 15.7 | Guard / Wrapper cho iOS 16+ | Ghi chú |
|---|---|---|---|
| Navigation | `NavigationView` (`.stack`) | `AppNavigationContainer` dùng `NavigationStack` trên iOS 16+ | Giữ luồng đồng nhất |
| Share Sheet | `UIActivityViewController` (`UIViewControllerRepresentable`) | Không dùng `ShareLink` (iOS 16+) | Chạy ổn định từ 15.7+ |
| Value Change | `onChange(of:perform:)` | Wrapper `onValueChange` phân nhánh `#if compiler(>=5.9)` + `#available(iOS 17.0, *)` | Không lỗi compiler Xcode 14 hoặc deprecation Xcode 15+ |
| Sleep / Tick | `Task.sleep(nanoseconds:)` | Không dùng `ContinuousClock` / `Task.sleep(for:)` (iOS 16+) | An toàn trên 15.7 |
| Storage URL | `FileManager.default.urls(for: .applicationSupportDirectory, ...)` + `appendingPathComponent` | Không dùng `URL.applicationSupportDirectory` (iOS 16+) | Chuẩn Foundation |
| Monotonic Clock | `mach_continuous_time()` + `mach_timebase_info` | Không phụ thuộc API iOS 16+ | Khai báo Privacy Manifest `NSPrivacyAccessedAPICategorySystemBootTime` (`35F9.1`) |
| Vision Person | `VNDetectHumanRectanglesRequest` (`upperBodyOnly = true` iOS 15+) + `VNDetectFaceRectanglesRequest` | Không dùng API Vision iOS 16/17+ | Tương thích iOS 15.7 |
| Guided Access | `UIAccessibility.isGuidedAccessEnabled` + `guidedAccessStatusDidChangeNotification` | Không gọi `requestGuidedAccessSession` ở bản unmanaged | Đọc thật từ hệ thống |
| Dynamic Type & Layout | `@Environment(\.dynamicTypeSize)` (`isAccessibilitySize`, iOS 15.0+) + `AdaptiveStack` | Không dùng `ViewThatFits` (iOS 16+) | Đảm bảo nút Trợ giúp/Kết thúc luôn chạm được trên SE tới Pro Max |

## Trạng thái xác minh thực tế
- iOS 15.7.x thiết bị thật: **NOT RUN — thiếu thiết bị & macOS/Xcode**.
- iOS mới hơn (16/17/18+) thiết bị thật & simulator: **NOT RUN — thiếu thiết bị & macOS/Xcode**.
