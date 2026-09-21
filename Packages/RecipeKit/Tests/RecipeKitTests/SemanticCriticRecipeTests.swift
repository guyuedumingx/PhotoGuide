import XCTest
@testable import RecipeKit

final class SemanticCriticRecipeTests: XCTestCase {
  func testEveryBundledRecipeDeclaresSemanticCriticProfile() {
    for preset in RecipePreset.allCases {
      let recipe = RecipeLoader().load(preset)
      let profile = recipe.source.resolvedCritic
      XCTAssertGreaterThanOrEqual(profile.dimensions.count, 5, "\(preset.rawValue) needs a real multi-dimensional critic profile")
      XCTAssertTrue(profile.dimensions.contains { $0.id == "composition" })
      XCTAssertFalse(profile.intent.isEmpty)
    }
  }

  func testCriticProfilesAreDomainSpecificNotPortraitCopies() {
    let portrait = RecipeLoader().load(.soloPortrait).source.resolvedCritic
    let food = RecipeLoader().load(.food).source.resolvedCritic
    let landscape = RecipeLoader().load(.landscape).source.resolvedCritic
    XCTAssertTrue(portrait.dimensions.contains { $0.id == "expression_pose" })
    XCTAssertTrue(food.dimensions.contains { $0.id == "food_presentation" })
    XCTAssertTrue(landscape.dimensions.contains { $0.id == "depth" })
    XCTAssertFalse(landscape.dimensions.contains { $0.id == "expression_pose" })
  }
}

extension SemanticCriticRecipeTests {
  func testEveryBundledRecipeHasExplicitReadyQualityGates() {
    for preset in RecipePreset.allCases {
      let profile = RecipeLoader().load(preset).source.resolvedCritic
      let required = profile.dimensions.filter(\.requiredForReady)
      XCTAssertGreaterThanOrEqual(required.count, 2, "\(preset.rawValue) needs at least two explicit READY gates")
      XCTAssertTrue(required.allSatisfy { $0.minimumConfidence >= 0.5 })
    }
  }

  func testCriticOnlyAblationPreservesAllQualityDimensions() {
    let analyzer = CriticAblationAnalyzer()
    for preset in RecipePreset.allCases {
      let recipe = RecipeLoader().load(preset)
      let result = analyzer.analyze(recipe, profile: .criticOnly)
      XCTAssertEqual(result.qualityDimensionCoverage, 1, "\(preset.rawValue) loses quality dimensions without local Vision")
      XCTAssertTrue(result.fullProductCapability)
    }
  }
}

extension SemanticCriticRecipeTests {
  func testCriticOnlyRecipeDoesNotNeedLegacyGoalsActionsOrLocalPerception() throws {
    let json = #"""
    {
      "kind":"Recipe",
      "id":"test.critic_only",
      "version":"0.8.0",
      "title":"Critic only",
      "subtitle":"Model-defined photography guidance",
      "nodes":[],
      "relations":[],
      "goals":[],
      "actions":[],
      "authorPolicy":{"allowGoalSkip":true,"allowGoalLock":true,"allowVariantSwitch":true},
      "critic":{
        "intent":"Judge this image professionally.",
        "preferredSampleCount":3,
        "dimensions":[
          {"id":"composition","name":"Composition","rubric":"Judge framing.","weight":1,"targetScore":0.8,"actionability":1,"requiredForReady":true,"minimumConfidence":0.5},
          {"id":"lighting","name":"Lighting","rubric":"Judge light.","weight":1,"targetScore":0.8,"actionability":1,"requiredForReady":true,"minimumConfidence":0.5},
          {"id":"color","name":"Color","rubric":"Judge color.","weight":0.7,"targetScore":0.75,"actionability":0.5},
          {"id":"clarity","name":"Clarity","rubric":"Judge clarity.","weight":0.8,"targetScore":0.75,"actionability":0.7},
          {"id":"overall","name":"Overall","rubric":"Judge overall image quality.","weight":0.8,"targetScore":0.78,"actionability":0.4}
        ]
      }
    }
    """#
    let dto = try JSONDecoder().decode(RecipeDTO.self, from: Data(json.utf8))
    let compiled = RecipeLoader().compile(dto)
    XCTAssertTrue(compiled.isValid)
    XCTAssertTrue(compiled.goals.isEmpty)
    XCTAssertTrue(compiled.actions.isEmpty)
    XCTAssertEqual(compiled.source.resolvedPerception.subjectStrategy, .scene)
    XCTAssertEqual(compiled.source.resolvedCritic.dimensions.count, 5)
  }
  func testUserCriticOnlyRecipeFactoryCompilesWithoutLegacyControlGraph() {
    let dto = RecipeFactory.criticOnly(
      id: "user.test.reference",
      title: "Reference",
      subtitle: "Generated from one reference image",
      intent: "Reproduce the reference image intent with live actionable guidance.")
    let compiled = RecipeLoader().compile(dto)

    XCTAssertTrue(compiled.isValid, compiled.validationIssues.map(\.message).joined(separator: "\n"))
    XCTAssertTrue(compiled.goals.isEmpty)
    XCTAssertTrue(compiled.actions.isEmpty)
    XCTAssertTrue(dto.nodes.isEmpty)
    XCTAssertGreaterThanOrEqual(dto.resolvedCritic.dimensions.count, 5)
  }

}
