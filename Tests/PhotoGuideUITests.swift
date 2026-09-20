import XCTest

@MainActor
final class PhotoGuideUITests: XCTestCase {
    func testSimulatorCompletesTheRealGuidanceLoop() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["环境人像"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 / 8"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["拍摄"].isEnabled)

        for satisfiedCount in 3...8 {
            let done = app.buttons["好了"]
            XCTAssertTrue(done.waitForExistence(timeout: 4))
            done.tap()
            XCTAssertTrue(
                app.staticTexts["\(satisfiedCount) / 8"].waitForExistence(timeout: 4),
                "Expected progress to reach \(satisfiedCount) / 8"
            )
        }

        XCTAssertTrue(app.staticTexts["构图可以了，拍吧"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["拍摄"].isEnabled)
        app.buttons["拍摄"].tap()
        XCTAssertTrue(app.staticTexts["模拟器只验证控制闭环，请在 iPhone 上拍摄"].waitForExistence(timeout: 2))
    }

    func testControlMenuExposesLockSkipAndReset() {
        let app = XCUIApplication()
        app.launch()

        let more = app.buttons["更多"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.buttons["保持当前构图"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["跳过当前目标"].exists)
        XCTAssertTrue(app.buttons["重新开始"].exists)
    }
}
