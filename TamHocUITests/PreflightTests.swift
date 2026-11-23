import XCTest

final class PreflightTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCannotStartWithoutGuidedAccess() {
        let app = XCUIApplication.launchedForTamHoc(arguments: ["-uitest"])

        app.turnOffCameraToggleIfOn()
        app.buttons["home.continue"].tap()

        let lockStatus = app.staticTexts["preflight.lockStatus"]
        XCTAssertTrue(lockStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(lockStatus.label, "Chưa bật")

        let startBtn = app.buttons["preflight.start"]
        XCTAssertTrue(startBtn.exists)
        XCTAssertFalse(startBtn.isEnabled)
    }

    func testCameraDeniedOffersTimerOnly() {
        let app = XCUIApplication.launchedForTamHoc(arguments: [
            "-uitest",
            "-uitest-lock-on",
            "-uitest-camera-denied"
        ])

        // Keep camera mode enabled and continue
        let continueBtn = app.buttons["home.continue"]
        XCTAssertTrue(continueBtn.waitForExistence(timeout: 5))
        continueBtn.tap()

        let fallbackBtn = app.buttons["preflight.useTimerOnly"]
        XCTAssertTrue(fallbackBtn.waitForExistence(timeout: 5))
        fallbackBtn.tap()

        let startBtn = app.buttons["preflight.start"]
        XCTAssertTrue(startBtn.isEnabled)
    }
}
