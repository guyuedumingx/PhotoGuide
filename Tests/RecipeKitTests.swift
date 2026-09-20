import GuidanceCore
import XCTest

@testable import RecipeKit

final class RecipeKitTests: XCTestCase {
  func testEnvironmentalPortraitRecipeIsExecutable() {
    let recipe = RecipeLoader().loadEnvironmentalPortrait()
    XCTAssertEqual(recipe.source.id, "official.environment_portrait")
    XCTAssertEqual(recipe.goals.count, 8)
    XCTAssertTrue(recipe.isValid, recipe.validationIssues.map(\.message).joined(separator: "\n"))
  }

  func testRelationGoalsUseRelationBinding() {
    let recipe = RecipeLoader().loadEnvironmentalPortrait()
    XCTAssertEqual(
      recipe.goals.first { $0.id == GoalID("relative_scale") }?.binding,
      .relation(RelationID("primary_anchor"))
    )
  }

  func testConcreteActionProtocolIsLoaded() {
    let recipe = RecipeLoader().loadEnvironmentalPortrait()
    let action = recipe.actions.first { $0.id == ActionID("subject.right") }
    XCTAssertEqual(action?.actor, .subject)
    XCTAssertEqual(action?.operation, .move)
    XCTAssertEqual(action?.direction, .right)
    XCTAssertEqual(action?.coordinateFrame, .imageSpace)
  }
}
