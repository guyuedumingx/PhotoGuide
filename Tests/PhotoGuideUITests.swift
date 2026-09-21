import XCTest

@MainActor
final class PhotoGuideUITests: XCTestCase {
  private func app(language: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    if let language { app.launchArguments += ["-AppleLanguages", "(\(language))"] }
    return app
  }

  private func attachScreenshot(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testLaunchesDirectlyIntoCamera() {
    let app = app(language: "zh-Hans")
    app.launch()
    XCTAssertTrue(app.buttons["camera.menu"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["camera.shutter"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["home.allRecipes"].exists)
    XCTAssertFalse(app.buttons["onboarding.continue"].exists)
    attachScreenshot(app, name: "camera-first")
  }

  func testMenuOnlyExposesRecipeSquareMineAndCreate() {
    let app = app(language: "zh-Hans")
    app.launch()
    let menu = app.buttons["camera.menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 5))
    menu.tap()
    XCTAssertTrue(app.staticTexts["Recipe 广场"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["我的 Recipe"].exists)
    XCTAssertTrue(app.staticTexts["创建 Recipe"].exists)
  }


  func testCameraOffersDirectRecipeQuickPicker() {
    let app = app(language: "zh-Hans")
    app.launch()

    let quick = app.buttons["camera.recipeQuick"]
    XCTAssertTrue(quick.waitForExistence(timeout: 5))
    quick.tap()

    XCTAssertTrue(app.otherElements["camera.recipeTray"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["camera.recipeManage"].exists)

    app.buttons["camera.recipeManage"].tap()
    XCTAssertTrue(app.staticTexts["Recipe 广场"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["我的 Recipe"].exists)
    XCTAssertTrue(app.staticTexts["创建 Recipe"].exists)
  }

  func testGuidanceLayoutSwitchesBetweenOverlayAndSplit() {
    let app = app(language: "zh-Hans")
    app.launch()
    let toggle = app.buttons["camera.guidanceLayout"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    toggle.tap()
    XCTAssertTrue(app.otherElements["camera.splitGuidancePanel"].waitForExistence(timeout: 2))
    toggle.tap()
    XCTAssertFalse(app.otherElements["camera.splitGuidancePanel"].exists)
  }

  func testSimulatorCaptureRemainsContinuous() throws {
    let app = app(language: "zh-Hans")
    app.launch()
    let shutter = app.buttons["camera.shutter"]
    XCTAssertTrue(shutter.waitForExistence(timeout: 5))
    guard !app.buttons["camera.switch"].isEnabled else {
      throw XCTSkip("Simulator-only continuous capture test")
    }
    shutter.tap()
    XCTAssertTrue(shutter.exists)
    XCTAssertTrue(shutter.isEnabled)
    shutter.tap()
    XCTAssertTrue(shutter.exists)
    XCTAssertFalse(app.otherElements["critic.report"].exists)
    XCTAssertFalse(app.buttons["capture.review.continue"].exists)
  }
}
