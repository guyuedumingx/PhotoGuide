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
    XCTAssertTrue(app.buttons["camera.recipe"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["camera.shutter"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons.matching(identifier: "camera.recipe").count, 1)
    XCTAssertFalse(app.buttons["camera.menu"].exists)
    XCTAssertFalse(app.buttons["camera.recipeQuick"].exists)
    XCTAssertFalse(app.buttons["camera.guidanceLayout"].exists)
    XCTAssertFalse(app.buttons["home.allRecipes"].exists)
    XCTAssertFalse(app.buttons["onboarding.continue"].exists)
    attachScreenshot(app, name: "camera-first")
  }

  func testUnifiedRecipeEntryReachesManagement() {
    let app = app(language: "zh-Hans")
    app.launch()
    let recipe = app.buttons["camera.recipe"]
    XCTAssertTrue(recipe.waitForExistence(timeout: 5))
    recipe.tap()
    XCTAssertTrue(app.otherElements["camera.recipeTray"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["camera.recipeManage"].exists)
    app.buttons["camera.recipeManage"].tap()
    XCTAssertTrue(app.staticTexts["Recipe 广场"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["我的 Recipe"].exists)
    XCTAssertTrue(app.staticTexts["创建 Recipe"].exists)
  }

  func testRecipeTrayDismissesBackToFullscreenCamera() {
    let app = app(language: "zh-Hans")
    app.launch()

    let recipe = app.buttons["camera.recipe"]
    XCTAssertTrue(recipe.waitForExistence(timeout: 5))
    recipe.tap()

    XCTAssertTrue(app.otherElements["camera.recipeTray"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["camera.recipeDismiss"].exists)
    app.buttons["camera.recipeDismiss"].tap()
    XCTAssertFalse(app.otherElements["camera.recipeTray"].exists)
    XCTAssertTrue(app.buttons["camera.shutter"].exists)
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
