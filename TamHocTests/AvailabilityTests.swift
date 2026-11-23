import XCTest
import StudyCore
@testable import TamHoc

final class AvailabilityTests: XCTestCase {
    func testDeploymentFloorIs157() throws {
        // Verify StudyCore floor constant matches 15.7 requirement
        XCTAssertEqual(StudyCoreInfo.minimumSupportedIOSVersion, "15.7")

        // Verify running OS meets at least iOS 15.7
        XCTAssertTrue(
            ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 0)
            ),
            "App must support running on iOS 15.7+"
        )

        // Verify built app bundle MinimumOSVersion does not exceed 15.7
        let info = Bundle.main.infoDictionary
        if let minOS = info?["MinimumOSVersion"] as? String {
            let parts = minOS.split(separator: ".").compactMap { Int($0) }
            XCTAssertGreaterThanOrEqual(parts.count, 2, "Unexpected MinimumOSVersion format: \(minOS)")
            let major = parts[0]
            let minor = parts[1]
            XCTAssertTrue(
                major < 15 || (major == 15 && minor <= 7),
                "Deployment floor drifted above 15.7: \(minOS)"
            )
            XCTAssertEqual(minOS, "15.7", "Expected exact MinimumOSVersion 15.7")
        }
    }

    func testCameraUsageDescriptionIsPresentAndMinimal() {
        let info = Bundle.main.infoDictionary
        let cameraDescription = info?["NSCameraUsageDescription"] as? String
        XCTAssertEqual(
            cameraDescription,
            "Tâm Học dùng camera để xác nhận bạn còn ở vị trí học. Hình ảnh được xử lý trên thiết bị, không được lưu hoặc gửi đi."
        )
    }

    func testNoForbiddenPrivacyPermissions() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertNil(info["NSMicrophoneUsageDescription"])
        XCTAssertNil(info["NSPhotoLibraryUsageDescription"])
        XCTAssertNil(info["NSPhotoLibraryAddUsageDescription"])
        XCTAssertNil(info["NSLocationWhenInUseUsageDescription"])
        XCTAssertNil(info["NSLocationAlwaysUsageDescription"])
        XCTAssertNil(info["NSLocationAlwaysAndWhenInUseUsageDescription"])
        XCTAssertNil(info["UIBackgroundModes"])
    }

    @MainActor
    func testReleaseBuildHasNoUITestBypass() {
        #if !DEBUG
        XCTAssertFalse(AppEnvironment.isUITestHarnessEnabled)
        #endif
    }
}
