import GuidanceCore
import XCTest

@testable import RecipeKit

final class RecipeKitTests: XCTestCase {
  func testBundledRecipeCompilesWithoutErrors() {
    let recipe = RecipeLoader().loadEnvironmentalPortrait()
    XCTAssertEqual(recipe.source.id, "official.environment_portrait")
    XCTAssertEqual(recipe.goals.count, 8)
    XCTAssertGreaterThanOrEqual(recipe.actions.count, 12)
    XCTAssertTrue(
      recipe.isValid,
      recipe.validationIssues.map { "\($0.rule.rawValue): \($0.message)" }.joined(separator: "\n"))
  }

  func testRecipeUsesRealRelationBinding() {
    let recipe = RecipeLoader().loadEnvironmentalPortrait()
    let relationGoal = recipe.goals.first { $0.id == GoalID("relative_scale") }
    XCTAssertEqual(relationGoal?.binding, .relation(RelationID("primary_anchor")))
    XCTAssertNotNil(recipe.registry.relations[RelationID("primary_anchor")])
  }

  func testActionsAreSemanticNotUIStrings() {
    let recipe = RecipeLoader().loadEnvironmentalPortrait()
    let right = recipe.actions.first { $0.id == ActionID("subject.right") }
    XCTAssertEqual(right?.actor, .subject)
    XCTAssertEqual(right?.operation, .move)
    XCTAssertEqual(right?.direction, .right)
    XCTAssertEqual(right?.coordinateFrame, .imageSpace)
  }

  func testHardGoalsAreNotSkippable() {
    let recipe = RecipeLoader().loadEnvironmentalPortrait()
    let hard = recipe.goals.filter { $0.constraint == .hard }
    XCTAssertTrue(hard.allSatisfy { !$0.skippable })
  }

  func testLowBurdenZoomWinsOverWalkingWhenAvailable() {
    let recipe = RecipeLoader().loadEnvironmentalPortrait()
    let session = GuidanceSession(goals: recipe.goals, actions: recipe.actions)
    session.engine.enterFramesOverride = 1
    session.engine.exitFramesOverride = 1
    session.planner.capabilities.insert("zoom.out")

    let primary: Binding = .node(NodeID("primary"))
    let relation: Binding = .relation(RelationID("primary_anchor"))
    let observations: [(DimensionID, Binding, DimensionValue)] = [
      (DimensionID("std.node.exists"), primary, .boolean(true)),
      (DimensionID("std.node.visibility"), primary, .boolean(true)),
      (DimensionID("std.node.visual_scale"), primary, .continuous(0.38)),
      (DimensionID("std.node.position_x"), primary, .continuous(0.65)),
      (DimensionID("std.node.position_y"), primary, .continuous(0.50)),
      (DimensionID("std.pose.body_orientation"), primary, .ordinal(0)),
      (DimensionID("std.relation.relative_scale"), relation, .ordinal(0)),
      (DimensionID("std.relation.visual_balance"), relation, .ordinal(0)),
    ]
    for (dimension, binding, value) in observations {
      _ = session.ingest(
        .init(dimension: dimension, binding: binding, value: value, confidence: 0.95, frameID: 1))
    }
    XCTAssertEqual(
      session.tick(), .propose(recipe.actions.first { $0.id == ActionID("camera.zoom.out.scale") }!)
    )
  }

  func testRecipeContainsExplicitInformationSeekingActions() {
    let recipe = RecipeLoader().loadEnvironmentalPortrait()
    let hold = recipe.actions.first { $0.id == ActionID("system.hold_for_evidence") }
    let semanticWait = recipe.actions.first { $0.id == ActionID("system.wait_semantic") }
    let anchor = recipe.actions.first { $0.id == ActionID("user.reselect_anchor") }

    XCTAssertEqual(hold?.operation, .hold)
    XCTAssertTrue(hold?.isInformationSeeking == true)
    XCTAssertEqual(semanticWait?.operation, .wait)
    XCTAssertTrue(semanticWait?.informationGoals.contains(GoalID("relative_scale")) == true)
    XCTAssertEqual(anchor?.operation, .selectAnchor)
  }

}
