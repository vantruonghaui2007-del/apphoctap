import XCTest

final class AccessibilityTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLargeTextKeepsHelpReachable() {
        let app = XCUIApplication.launchedForTamHoc(arguments: [
            "-uitest",
            "-uitest-lock-on",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ])

        app.startTimerOnlySessionFromHome()

        let helpBtn = app.buttons["focus.help"]
        XCTAssertTrue(helpBtn.waitForExistence(timeout: 5))
        if !helpBtn.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(helpBtn.isHittable)
        helpBtn.tap()

        XCTAssertTrue(app.staticTexts["Cách bật và thoát Guided Access"].waitForExistence(timeout: 5))
    }
}
