import XCTest

extension XCUIApplication {
    static func launchedForTamHoc(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    func turnOffCameraToggleIfOn() {
        let toggle = switches["home.cameraToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String) == "1" {
            toggle.tap()
        }
    }

    func startTimerOnlySessionFromHome() {
        turnOffCameraToggleIfOn()
        let continueBtn = buttons["home.continue"]
        XCTAssertTrue(continueBtn.waitForExistence(timeout: 5))
        continueBtn.tap()

        let startBtn = buttons["preflight.start"]
        XCTAssertTrue(startBtn.waitForExistence(timeout: 5))
        XCTAssertTrue(startBtn.isEnabled)
        startBtn.tap()
    }
}
