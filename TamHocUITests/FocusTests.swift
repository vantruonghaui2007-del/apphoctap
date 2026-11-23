import XCTest

final class FocusTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTimerOnlySummaryIsNotVerified() {
        let app = XCUIApplication.launchedForTamHoc(arguments: ["-uitest", "-uitest-lock-on"])

        app.startTimerOnlySessionFromHome()

        let remaining = app.staticTexts["focus.remaining"]
        XCTAssertTrue(remaining.waitForExistence(timeout: 5))

        let presence = app.descendants(matching: .any)["focus.presence"]
        XCTAssertTrue(presence.exists)
        XCTAssertTrue(presence.label.contains("Không dùng camera"))
        XCTAssertFalse(presence.label.contains("Có mặt"))

        app.buttons["focus.endEarly"].tap()
        let confirmStop = app.buttons["Dừng phiên học"]
        XCTAssertTrue(confirmStop.waitForExistence(timeout: 5))
        confirmStop.tap()

        let summaryStatus = app.staticTexts["summary.status"]
        XCTAssertTrue(summaryStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["summary.unverifiedNotice"].exists)
        XCTAssertFalse(app.staticTexts["Có mặt (đã xác nhận)"].exists)
    }

    func testCompletionStillExplainsGuidedAccessExit() {
        let app = XCUIApplication.launchedForTamHoc(arguments: ["-uitest", "-uitest-lock-on"])

        app.startTimerOnlySessionFromHome()

        XCTAssertTrue(app.buttons["focus.endEarly"].waitForExistence(timeout: 5))
        app.buttons["focus.endEarly"].tap()
        app.buttons["Dừng phiên học"].tap()

        XCTAssertTrue(app.staticTexts["summary.status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Guided Access vẫn đang bật"].exists)
        XCTAssertTrue(app.buttons["summary.guidedAccessHelp"].exists)
    }
}
