import XCTest
@testable import GuidanceCore

final class VisualJudgeTests: XCTestCase {
  func test_choice_question_returns_recipe_issue_without_action() {
    let q = VisualQuestion(
      id: "angle", title: "Angle", prompt: "Compare camera angle",
      answerSpec: .choice(options: [
        .init(id: "too_high", label: "Too high", issue: "拍摄角度偏高"),
        .init(id: "matched", label: "Matched"),
        .init(id: "too_low", label: "Too low", issue: "拍摄角度偏低"),
      ]))
    XCTAssertEqual(q.answerSpec.evaluate(.choice("too_high")), "拍摄角度偏高")
    XCTAssertNil(q.answerSpec.evaluate(.choice("matched")))
  }

  func test_skip_removes_question_from_scheduler_until_restored() {
    let a = VisualQuestion(id: "a", title: "A", prompt: "A?", answerSpec: .boolean(expected: true, mismatchIssue: "A bad"))
    let b = VisualQuestion(id: "b", title: "B", prompt: "B?", answerSpec: .boolean(expected: true, mismatchIssue: "B bad"))
    var runtime = QuestionRuntime(questions: [a, b])
    runtime.skip("a")
    XCTAssertEqual(runtime.nextQuestion()?.id, "b")
    runtime.restore("a")
    XCTAssertEqual(runtime.nextQuestion()?.id, "a")
  }

  func test_issues_are_exposed_in_recipe_author_order() {
    let first = VisualQuestion(id: "first", title: "First", prompt: "?", answerSpec: .boolean(expected: true, mismatchIssue: "first issue"))
    let second = VisualQuestion(id: "second", title: "Second", prompt: "?", answerSpec: .boolean(expected: true, mismatchIssue: "second issue"))
    var runtime = QuestionRuntime(questions: [first, second])
    runtime.record(.boolean(false), for: "second")
    runtime.record(.boolean(false), for: "first")
    XCTAssertEqual(runtime.issueSnapshots().map(\.id), ["first", "second"])
    XCTAssertEqual(runtime.firstIssue()?.id, "first")
  }

  func test_scheduler_evaluates_unseen_questions_in_author_order() {
    let a = VisualQuestion(id: "a", title: "A", prompt: "A?", answerSpec: .boolean(expected: true, mismatchIssue: "A bad"))
    let b = VisualQuestion(id: "b", title: "B", prompt: "B?", answerSpec: .boolean(expected: true, mismatchIssue: "B bad"))
    var runtime = QuestionRuntime(questions: [a, b])
    let now = Date()
    XCTAssertEqual(runtime.nextQuestion(at: now)?.id, "a")
    runtime.record(.boolean(true), for: "a", at: now)
    XCTAssertEqual(runtime.nextQuestion(at: now)?.id, "b")
  }

  func test_matched_questions_are_periodically_rechecked() {
    let q = VisualQuestion(id: "q", title: "Q", prompt: "?", answerSpec: .boolean(expected: true, mismatchIssue: "bad"))
    var runtime = QuestionRuntime(questions: [q])
    let now = Date()
    runtime.record(.boolean(true), for: "q", at: now)
    XCTAssertEqual(runtime.snapshots().first?.status, .matched)
    XCTAssertNil(runtime.nextQuestion(at: now.addingTimeInterval(1.0)))
    XCTAssertEqual(runtime.nextQuestion(at: now.addingTimeInterval(3.1))?.id, "q")
  }

  func test_score_returns_only_problem_text() {
    let spec = JudgeAnswerSpec.score(range: 0...100, expected: 80...100, belowIssue: "相似度偏低", aboveIssue: nil)
    XCTAssertEqual(spec.evaluate(.score(20)), "相似度偏低")
    XCTAssertEqual(spec.evaluate(.score(75)), "相似度偏低")
    XCTAssertNil(spec.evaluate(.score(88)))
  }

  func testInvalidJudgeAnswerIsNeverTreatedAsMatched() {
    let question = VisualQuestion(
      id: "angle", title: "Angle", prompt: "Compare angle",
      answerSpec: .choice(options: [
        .init(id: "high", label: "High", issue: "Too high"),
        .init(id: "match", label: "Match"),
      ]))
    var runtime = QuestionRuntime(questions: [question])
    runtime.record(.choice("unknown"), for: "angle")
    let state = runtime.snapshots()[0]
    XCTAssertEqual(state.status, .pending)
    XCTAssertNil(state.answer)
    XCTAssertNil(state.issue)
  }
}
