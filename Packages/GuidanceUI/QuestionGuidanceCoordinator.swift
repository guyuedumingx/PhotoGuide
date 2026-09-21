import CameraRuntime
import Foundation
import GuidanceCore
import PerceptionRuntime
import RecipeKit

@MainActor
final class QuestionGuidanceCoordinator {
  private(set) var runtime: QuestionRuntime
  let references: [VisualReference]
  let judge: (any VisualJudge)?

  private var task: Task<Void, Never>?
  private var inFlight = false
  private var lastRequestAt = Date.distantPast
  private var generation = 0

  init(recipe: RecipeDTO, judge: (any VisualJudge)?) {
    runtime = QuestionRuntime(questions: recipe.resolvedVisualQuestions)
    references = recipe.resolvedVisualReferences
    self.judge = judge
  }

  var isConfigured: Bool { !runtime.questions.isEmpty && !references.isEmpty }
  var canEvaluate: Bool { isConfigured && judge != nil }
  var snapshots: [QuestionRuntimeSnapshot] { runtime.snapshots() }
  var issues: [QuestionRuntimeSnapshot] { runtime.issueSnapshots() }
  var firstIssue: QuestionRuntimeSnapshot? { runtime.firstIssue() }
  var currentQuestion: VisualQuestion? { runtime.nextQuestion() }

  func reset() {
    task?.cancel()
    task = nil
    inFlight = false
    generation &+= 1
    runtime.reset()
  }

  func invalidateAnswersPreservingSkips() {
    let skipped = Set(runtime.snapshots().filter { $0.status == .skipped }.map(\.id))
    task?.cancel()
    task = nil
    inFlight = false
    generation &+= 1
    runtime.reset()
    for id in skipped { runtime.skip(id) }
  }

  func skip(_ id: String) {
    runtime.skip(id)
    task?.cancel()
    task = nil
    inFlight = false
    generation &+= 1
  }

  func restore(_ id: String) {
    runtime.restore(id)
    generation &+= 1
  }

  func restoreAll() {
    for snapshot in runtime.snapshots() where snapshot.status == .skipped { runtime.restore(snapshot.id) }
    generation &+= 1
  }

  func schedule(frame: CameraFrame, onUpdate: @escaping @MainActor () -> Void) {
    guard let judge, isConfigured, !inFlight,
      Date().timeIntervalSince(lastRequestAt) >= 0.48,
      let question = runtime.nextQuestion()
    else { return }

    inFlight = true
    lastRequestAt = .now
    let requestGeneration = generation
    let frameID = frame.id
    let references = references
    let frameForEncoding = frame

    task = Task { [weak self] in
      guard let self else { return }
      defer {
        inFlight = false
        task = nil
      }

      let payload = await Task.detached(priority: .utility) {
        SemanticFrameEncoder.jpegData(from: frameForEncoding.pixelBuffer, maxDimension: 640, quality: 0.62)
      }.value
      guard !Task.isCancelled, let payload else { return }

      do {
        let answer = try await judge.judge(
          VisualJudgeRequest(
            currentFrameID: frameID,
            currentFrame: payload,
            references: references,
            question: question,
            locale: Locale.preferredLanguages.first ?? Locale.current.identifier))
        guard !Task.isCancelled, requestGeneration == generation else { return }
        runtime.record(answer, for: question.id)
        onUpdate()
      } catch {
        // DJev integration owns transport/retry policy. The question core keeps
        // the previous cached answers and simply waits for another opportunity.
        onUpdate()
      }
    }
  }
}

#if DEBUG
struct PreviewVisualJudge: VisualJudge {
  func judge(_ request: VisualJudgeRequest) async throws -> JudgeAnswer {
    // Deterministic UI test judge. It never inspects or claims to understand the
    // image. Real visual comparison remains the one intentionally missing DJev integration.
    let seed = stablePreviewSeed(frameID: request.currentFrameID, questionID: request.question.id)
    switch request.question.answerSpec {
    case .choice(let options):
      guard !options.isEmpty else { return .choice("") }
      return .choice(options[seed % options.count].id)
    case .score(let range, _, _, _):
      let unit = Double(seed % 101) / 100
      return .score(range.lowerBound + unit * (range.upperBound - range.lowerBound))
    case .boolean:
      return .boolean(seed.isMultiple(of: 3))
    }
  }

  private func stablePreviewSeed(frameID: Int, questionID: String) -> Int {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in questionID.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    hash ^= UInt64(bitPattern: Int64(frameID))
    return Int(hash % UInt64(Int.max))
  }

}
#endif
