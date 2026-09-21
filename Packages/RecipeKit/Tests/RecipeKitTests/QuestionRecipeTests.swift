import Foundation
import GuidanceCore
import XCTest
@testable import RecipeKit

final class QuestionRecipeTests: XCTestCase {
  func testQuestionRecipeCompilesWithoutGoalsActionsOrCritic() throws {
    let ref = RecipeReferenceDTO(id: "r", imageData: Data([1, 2, 3]))
    let recipe = RecipeFactory.questionRecipe(
      id: "user.test", title: "Test", subtitle: "",
      references: [ref], questions: RecipeFactory.defaultQuestions)
    let compiled = RecipeLoader().compile(recipe)
    XCTAssertTrue(compiled.isValid)
    XCTAssertTrue(recipe.goals.isEmpty)
    XCTAssertTrue(recipe.actions.isEmpty)
    XCTAssertNil(recipe.critic)
    XCTAssertFalse(recipe.resolvedVisualQuestions.isEmpty)
    XCTAssertEqual(recipe.resolvedVisualReferences.count, 1)
  }

  func testQuestionSchemaOnlyExposesChoiceScoreBoolean() {
    let types = Set(RecipeQuestionType.allCases)
    XCTAssertEqual(types, Set([.choice, .score, .boolean]))
  }

  func testChoiceRequiresAtLeastOneMatchedOption() {
    let invalid = RecipeQuestionDTO.choice(
      id: "angle", title: "Angle", prompt: "Angle?",
      options: [
        .init(id: "high", label: "High", issue: "Too high"),
        .init(id: "low", label: "Low", issue: "Too low")
      ])
    XCTAssertEqual(invalid.validate(), .invalidChoice("angle"))
  }

  func testDefaultQuestionsContainNoActionOrHintFields() throws {
    let data = try JSONEncoder().encode(RecipeFactory.defaultQuestions)
    let json = String(decoding: data, as: UTF8.self).lowercased()
    XCTAssertFalse(json.contains("action"))
    XCTAssertFalse(json.contains("hint"))
    XCTAssertFalse(json.contains("advice"))
  }

  func testReferenceRoundTripsInsidePortableRecipeJSON() throws {
    let bytes = Data([9, 8, 7, 6])
    let recipe = RecipeFactory.questionRecipe(
      id: "portable", title: "Portable", subtitle: "",
      references: [.init(id: "ref", imageData: bytes)],
      questions: [RecipeFactory.defaultQuestions[0]])
    let encoded = try JSONEncoder().encode(recipe)
    let decoded = try JSONDecoder().decode(RecipeDTO.self, from: encoded)
    XCTAssertEqual(decoded.resolvedVisualReferences.first?.imagePayload, bytes)
  }

  func testScoreRequiresIssueTextForEveryReachableMismatchSide() {
    let invalid = RecipeQuestionDTO.score(
      id: "similarity", title: "Similarity", prompt: "Compare",
      range: 0...100, expected: 80...100, belowIssue: nil)
    XCTAssertEqual(invalid.validate(), .invalidScore("similarity"))

    let valid = RecipeQuestionDTO.score(
      id: "similarity", title: "Similarity", prompt: "Compare",
      range: 0...100, expected: 80...100, belowIssue: "Too different")
    XCTAssertNil(valid.validate())
  }

}
