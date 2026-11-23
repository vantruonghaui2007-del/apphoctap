import XCTest

final class OnboardingTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWelcomeSafetyExplainsLimitsAndAdvancesToHome() {
        let app = XCUIApplication.launchedForTamHoc(arguments: ["-uitest", "-uitest-show-onboarding"])

        let continueBtn = app.buttons["welcome.continue"]
        XCTAssertTrue(continueBtn.waitForExistence(timeout: 5))
        continueBtn.tap()

        XCTAssertTrue(app.staticTexts["home.duration"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["home.cameraToggle"].exists)
    }
}
