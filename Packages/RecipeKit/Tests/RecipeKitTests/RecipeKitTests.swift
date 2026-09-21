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

  func testAllShippingPresetsCompileAndExposeExpectedAnchorPolicy() {
    let loader = RecipeLoader()
    let presets: [(RecipePreset, String, Bool)] = [
      (.environmentPortrait, "official.environment_portrait", true),
      (.soloPortrait, "official.solo_portrait", false),
      (.centeredPortrait, "official.centered_portrait", false),
      (.closeupPortrait, "official.closeup_portrait", false),
      (.travelPortrait, "official.travel_portrait", true),
      (.food, "official.food", false),
      (.flowerMacro, "official.flower_macro", false),
      (.landscape, "official.landscape", false),
      (.product, "official.product", false),
      (.pet, "official.pet", false),
      (.architecture, "official.architecture", false),
    ]

    for (preset, expectedID, requiresAnchor) in presets {
      let recipe = loader.load(preset)
      XCTAssertEqual(recipe.source.id, expectedID)
      XCTAssertEqual(preset.requiresSceneAnchor, requiresAnchor)
      XCTAssertTrue(
        recipe.isValid,
        "\(preset.rawValue): "
          + recipe.validationIssues.map { "\($0.rule.rawValue): \($0.message)" }.joined(separator: "\n"))
    }
  }

  func testPoseNeverBlocksCaptureAsARequiredGuard() {
    let loader = RecipeLoader()
    for preset in RecipePreset.allCases {
      let recipe = loader.load(preset)
      if let pose = recipe.goals.first(where: { $0.dimension == DimensionID("std.pose.body_orientation") }) {
        XCTAssertEqual(pose.constraint, .soft, "\(preset.rawValue) should not hard-block on pose")
      }
    }
  }

  func testContinuousActionThresholdsMatchGoalAcceptableBounds() {
    let loader = RecipeLoader()

    for preset in RecipePreset.allCases {
      let recipe = loader.load(preset)
      let goalByID = Dictionary(uniqueKeysWithValues: recipe.source.goals.map { ($0.id, $0) })

      for action in recipe.source.actions {
        let condition = action.condition
        guard let goalID = condition.goal, let threshold = condition.number else { continue }
        guard condition.type == "CONTINUOUS_BELOW" || condition.type == "CONTINUOUS_ABOVE" else { continue }
        guard let acceptable = goalByID[goalID]?.target.acceptable, acceptable.count == 2 else {
          XCTFail("\(preset.rawValue): \(action.id) must reference a continuous goal with an acceptable range")
          continue
        }

        let expected = condition.type == "CONTINUOUS_BELOW" ? acceptable[0] : acceptable[1]
        XCTAssertEqual(
          threshold, expected, accuracy: 0.000_001,
          "\(preset.rawValue): \(action.id) threshold drifted away from \(goalID) acceptable boundary")
      }
    }
  }


  func testCatalogSpansHumanObjectAndScenePerceptionStrategies() {
    let recipes = RecipeLoader().catalog()
    let strategies = Set(recipes.map { $0.source.resolvedPerception.subjectStrategy })
    XCTAssertTrue(strategies.contains(.human))
    XCTAssertTrue(strategies.contains(.saliency))
    XCTAssertTrue(strategies.contains(.scene))

    let domains = Set(recipes.map { $0.source.resolvedPresentation.domain })
    for required: RecipeDomain in [.portrait, .food, .nature, .product, .pet, .landscape, .architecture] {
      XCTAssertTrue(domains.contains(required), "shipping catalog must cover \(required.rawValue)")
    }
  }

  func testEveryShippingRecipeKeepsFullQualityCoverageWithoutLocalVision() {
    let analyzer = CriticAblationAnalyzer()
    for recipe in RecipeLoader().catalog() {
      let result = analyzer.analyze(recipe, profile: .criticOnly)
      XCTAssertEqual(result.qualityDimensionCoverage, 1, accuracy: 0.000_001)
      XCTAssertTrue(result.professionalAdviceAvailable)
      XCTAssertFalse(result.localAssistAvailable)
      XCTAssertTrue(result.fullProductCapability)
    }
  }

  func testLocalOnlyIsExplicitlyADegradedFallbackNotTheProductCore() {
    let analyzer = CriticAblationAnalyzer()
    for recipe in RecipeLoader().catalog() {
      let result = analyzer.analyze(recipe, profile: .localOnly)
      XCTAssertEqual(result.qualityDimensionCoverage, 0, accuracy: 0.000_001)
      XCTAssertFalse(result.professionalAdviceAvailable)
      XCTAssertFalse(result.fullProductCapability)
    }
  }

  func testSingleFrameKeepsDimensionCoverageButLosesTemporalContext() {
    let analyzer = CriticAblationAnalyzer()
    let result = analyzer.analyze(RecipeLoader().load(.pet), profile: .singleFrameCritic)
    XCTAssertEqual(result.qualityDimensionCoverage, 1, accuracy: 0.000_001)
    XCTAssertTrue(result.professionalAdviceAvailable)
    XCTAssertFalse(result.temporalContextAvailable)
  }

  func testGenericRubricAblationLosesDomainSpecificExpertise() {
    let analyzer = CriticAblationAnalyzer()
    for preset in [RecipePreset.food, .flowerMacro, .product, .pet, .landscape, .architecture] {
      let result = analyzer.analyze(RecipeLoader().load(preset), profile: .genericRubric)
      XCTAssertLessThan(result.qualityDimensionCoverage, 1)
      XCTAssertFalse(result.domainSpecificRubricAvailable)
      XCTAssertFalse(result.fullProductCapability)
    }
  }

  func testObjectRecipesDoNotDependOnPortraitPoseDimension() {
    let loader = RecipeLoader()
    for preset in [RecipePreset.food, .flowerMacro, .product, .pet] {
      let recipe = loader.load(preset)
      XCTAssertFalse(recipe.goals.contains { $0.dimension == DimensionID("std.pose.body_orientation") })
      XCTAssertEqual(recipe.source.resolvedPerception.subjectStrategy, .saliency)
    }
  }

  func testSceneRecipesDoNotDeclareRequiredPrimarySubject() {
    let loader = RecipeLoader()
    for preset in [RecipePreset.landscape, .architecture] {
      let recipe = loader.load(preset)
      XCTAssertNil(recipe.source.primarySubjectNode)
      XCTAssertEqual(recipe.source.resolvedPerception.subjectStrategy, .scene)
      XCTAssertFalse(recipe.goals.contains { $0.binding == .node(NodeID("primary")) })
    }
  }

}
