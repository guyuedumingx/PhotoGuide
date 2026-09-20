import XCTest

@MainActor
final class PhotoGuideUITests: XCTestCase {
  private func app(language: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    if let language {
      app.launchArguments += ["-AppleLanguages", "(\(language))"]
    }
    return app
  }

  private func openCamera(_ app: XCUIApplication) {
    let featured = app.buttons["home.featured.environmentPortrait"]
    XCTAssertTrue(featured.waitForExistence(timeout: 5))
    featured.tap()

    let start = app.buttons["recipe.start.environmentPortrait"]
    XCTAssertTrue(start.waitForExistence(timeout: 3))
    start.tap()
  }

  func testHomeRecipeDetailToCameraAndGuidanceLoop() {
    let app = app(language: "zh-Hans")
    app.launch()

    XCTAssertTrue(app.staticTexts["PhotoGuide"].waitForExistence(timeout: 5))
    openCamera(app)

    XCTAssertTrue(app.buttons["camera.recipeControls"].waitForExistence(timeout: 4))
    XCTAssertTrue(app.buttons["camera.shutter"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.buttons["camera.shutter"].isEnabled, "Shutter must remain user-controlled before READY")
  }

  func testRecipeLibraryIsReachableWithStableIdentifiers() {
    let app = app(language: "zh-Hans")
    app.launch()

    let browse = app.buttons["home.allRecipes"]
    XCTAssertTrue(browse.waitForExistence(timeout: 4))
    browse.tap()
    XCTAssertTrue(
      app.otherElements["recipe.library.title"].exists || app.staticTexts["拍摄配方"].exists)
    XCTAssertTrue(app.staticTexts["环境人像"].exists)
    XCTAssertTrue(app.staticTexts["夜景人像"].exists)
  }

  func testEnglishLocalizationUsesSameNavigationContract() {
    let app = app(language: "en")
    app.launch()

    XCTAssertTrue(app.staticTexts["Real-time photo coach"].waitForExistence(timeout: 5))
    let browse = app.buttons["home.allRecipes"]
    XCTAssertTrue(browse.exists)
    browse.tap()
    XCTAssertTrue(app.staticTexts["Photo recipes"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Environmental portrait"].exists)
    XCTAssertTrue(app.staticTexts["Night portrait"].exists)
  }

  func testControlMenuExposesHumanOverridesWithoutDependingOnLanguage() {
    let app = app(language: "en")
    app.launch()
    openCamera(app)

    let control = app.buttons["camera.recipeControls"]
    XCTAssertTrue(control.waitForExistence(timeout: 4))
    control.tap()
    XCTAssertTrue(app.buttons["control.lockComposition"].waitForExistence(timeout: 2))
    XCTAssertTrue(
      app.otherElements["control.exposure.title"].exists
        || app.staticTexts["Image brightness"].exists)
    XCTAssertTrue(app.buttons["control.restart"].exists)
  }
}
