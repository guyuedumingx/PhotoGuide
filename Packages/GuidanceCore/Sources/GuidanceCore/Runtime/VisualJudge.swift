import Foundation

/// PhotoGuide's minimal System-1 contract.
///
/// The model never plans actions and never writes coaching copy. A Recipe asks
/// one bounded visual comparison question about the current frame versus one or
/// more reference images. The judge returns only choice / score / boolean.
public enum VisualJudgeContract {
  public static let version = 1
}

public enum JudgeAnswer: Codable, Equatable, Sendable {
  case choice(String)
  case score(Double)
  case boolean(Bool)

  private enum CodingKeys: String, CodingKey { case type, value }
  private enum Kind: String, Codable { case choice, score, boolean }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .choice: self = .choice(try container.decode(String.self, forKey: .value))
    case .score: self = .score(try container.decode(Double.self, forKey: .value))
    case .boolean: self = .boolean(try container.decode(Bool.self, forKey: .value))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .choice(let value):
      try container.encode(Kind.choice, forKey: .type)
      try container.encode(value, forKey: .value)
    case .score(let value):
      try container.encode(Kind.score, forKey: .type)
      try container.encode(value, forKey: .value)
    case .boolean(let value):
      try container.encode(Kind.boolean, forKey: .type)
      try container.encode(value, forKey: .value)
    }
  }
}

public struct JudgeChoiceOption: Codable, Equatable, Hashable, Sendable {
  public let id: String
  public let label: String
  /// Nil means this answer matches the Recipe target and therefore has no issue.
  public let issue: String?
  public init(id: String, label: String, issue: String? = nil) {
    self.id = id
    self.label = label
    self.issue = issue
  }
}

public enum JudgeAnswerSpec: Codable, Equatable, Sendable {
  case choice(options: [JudgeChoiceOption])
  case score(range: ClosedRange<Double>, expected: ClosedRange<Double>, belowIssue: String?, aboveIssue: String?)
  case boolean(expected: Bool, mismatchIssue: String)

  private enum CodingKeys: String, CodingKey {
    case type, options, min, max, expectedMin, expectedMax, belowIssue, aboveIssue, expectedBoolean, mismatchIssue
  }
  private enum Kind: String, Codable { case choice, score, boolean }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    switch try c.decode(Kind.self, forKey: .type) {
    case .choice:
      self = .choice(options: try c.decode([JudgeChoiceOption].self, forKey: .options))
    case .score:
      let min = try c.decode(Double.self, forKey: .min)
      let max = try c.decode(Double.self, forKey: .max)
      let expectedMin = try c.decode(Double.self, forKey: .expectedMin)
      let expectedMax = try c.decode(Double.self, forKey: .expectedMax)
      self = .score(
        range: min...max,
        expected: expectedMin...expectedMax,
        belowIssue: try c.decodeIfPresent(String.self, forKey: .belowIssue),
        aboveIssue: try c.decodeIfPresent(String.self, forKey: .aboveIssue))
    case .boolean:
      self = .boolean(
        expected: try c.decode(Bool.self, forKey: .expectedBoolean),
        mismatchIssue: try c.decode(String.self, forKey: .mismatchIssue))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .choice(let options):
      try c.encode(Kind.choice, forKey: .type)
      try c.encode(options, forKey: .options)
    case .score(let range, let expected, let belowIssue, let aboveIssue):
      try c.encode(Kind.score, forKey: .type)
      try c.encode(range.lowerBound, forKey: .min)
      try c.encode(range.upperBound, forKey: .max)
      try c.encode(expected.lowerBound, forKey: .expectedMin)
      try c.encode(expected.upperBound, forKey: .expectedMax)
      try c.encodeIfPresent(belowIssue, forKey: .belowIssue)
      try c.encodeIfPresent(aboveIssue, forKey: .aboveIssue)
    case .boolean(let expected, let mismatchIssue):
      try c.encode(Kind.boolean, forKey: .type)
      try c.encode(expected, forKey: .expectedBoolean)
      try c.encode(mismatchIssue, forKey: .mismatchIssue)
    }
  }

  /// Strictly validates that a System-1 answer belongs to this question's bounded output space.
  /// Invalid/out-of-range answers are retried later and are never interpreted as a match.
  public func accepts(_ answer: JudgeAnswer) -> Bool {
    switch (self, answer) {
    case let (.choice(options), .choice(value)):
      return options.contains(where: { $0.id == value })
    case let (.score(range, _, _, _), .score(value)):
      return value.isFinite && range.contains(value)
    case (.boolean, .boolean):
      return true
    default:
      return false
    }
  }

  /// Returns nil when the answer matches the Recipe target. Otherwise returns
  /// only the Recipe-authored problem text. The core never ranks or plans actions.
  public func evaluate(_ answer: JudgeAnswer) -> String? {
    switch (self, answer) {
    case let (.choice(options), .choice(value)):
      guard let option = options.first(where: { $0.id == value }), let issue = option.issue, !issue.isEmpty else {
        return nil
      }
      return issue

    case let (.boolean(expected, issue), .boolean(value)):
      return value == expected ? nil : issue

    case let (.score(range, expected, belowIssue, aboveIssue), .score(raw)):
      guard raw.isFinite else { return nil }
      let value = min(max(raw, range.lowerBound), range.upperBound)
      if expected.contains(value) { return nil }
      if value < expected.lowerBound, let issue = belowIssue, !issue.isEmpty { return issue }
      if value > expected.upperBound, let issue = aboveIssue, !issue.isEmpty { return issue }
      return nil

    default:
      return nil
    }
  }

}

public struct VisualQuestion: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let prompt: String
  public let answerSpec: JudgeAnswerSpec

  public init(id: String, title: String, prompt: String, answerSpec: JudgeAnswerSpec) {
    self.id = id
    self.title = title
    self.prompt = prompt
    self.answerSpec = answerSpec
  }
}

public struct VisualReference: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let mimeType: String
  public let imagePayload: Data

  public init(id: String, mimeType: String = "image/jpeg", imagePayload: Data) {
    self.id = id
    self.mimeType = mimeType
    self.imagePayload = imagePayload
  }
}

public struct VisualJudgeRequest: Equatable, Sendable {
  public let currentFrameID: Int
  public let currentFrame: Data
  public let references: [VisualReference]
  public let question: VisualQuestion
  public let locale: String

  public init(
    currentFrameID: Int,
    currentFrame: Data,
    references: [VisualReference],
    question: VisualQuestion,
    locale: String
  ) {
    self.currentFrameID = currentFrameID
    self.currentFrame = currentFrame
    self.references = references
    self.question = question
    self.locale = locale
  }
}

public protocol VisualJudge: Sendable {
  func judge(_ request: VisualJudgeRequest) async throws -> JudgeAnswer
}

public enum QuestionRuntimeStatus: String, Codable, Equatable, Sendable {
  case pending
  case issue
  case matched
  case skipped
}

public struct QuestionRuntimeSnapshot: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let status: QuestionRuntimeStatus
  public let answer: JudgeAnswer?
  public let issue: String?
  public let lastEvaluatedAt: Date?

  public init(
    id: String,
    title: String,
    status: QuestionRuntimeStatus,
    answer: JudgeAnswer?,
    issue: String?,
    lastEvaluatedAt: Date?
  ) {
    self.id = id
    self.title = title
    self.status = status
    self.answer = answer
    self.issue = issue
    self.lastEvaluatedAt = lastEvaluatedAt
  }
}

/// Tiny scheduling/state layer for Recipe questions.
///
/// It never decides how the user should act. It only:
/// - stops sending skipped questions to the judge;
/// - keeps cached answers fresh;
/// - chooses which Recipe-authored issue text deserves the single UI slot.
public struct QuestionRuntime: Sendable {
  public let questions: [VisualQuestion]

  private struct State: Sendable {
    var status: QuestionRuntimeStatus = .pending
    var answer: JudgeAnswer?
    var issue: String?
    var lastEvaluatedAt: Date?
  }

  private var states: [String: State]

  public init(questions: [VisualQuestion]) {
    self.questions = questions
    self.states = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, State()) })
  }

  public mutating func reset() {
    states = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, State()) })
  }

  public mutating func skip(_ id: String) {
    guard var state = states[id] else { return }
    state.status = .skipped
    state.issue = nil
    states[id] = state
  }

  public mutating func restore(_ id: String) {
    guard var state = states[id] else { return }
    state.status = .pending
    state.answer = nil
    state.issue = nil
    state.lastEvaluatedAt = nil
    states[id] = state
  }

  public func isSkipped(_ id: String) -> Bool { states[id]?.status == .skipped }

  /// Scheduling is intentionally authored-order only. Every active question is
  /// evaluated once in array order, then periodically rechecked in that same order.
  public func nextQuestion(at now: Date = .now) -> VisualQuestion? {
    let active = questions.filter { states[$0.id]?.status != .skipped }
    guard !active.isEmpty else { return nil }

    if let unseen = active.first(where: { states[$0.id]?.lastEvaluatedAt == nil }) { return unseen }

    for question in active {
      guard let state = states[question.id], let last = state.lastEvaluatedAt else { return question }
      let interval: TimeInterval = state.status == .issue ? 0.9 : 2.8
      if now.timeIntervalSince(last) >= interval { return question }
    }
    return nil
  }

  public mutating func record(_ answer: JudgeAnswer, for questionID: String, at date: Date = .now) {
    guard var state = states[questionID], state.status != .skipped,
      let question = questions.first(where: { $0.id == questionID }),
      question.answerSpec.accepts(answer)
    else { return }

    state.answer = answer
    state.lastEvaluatedAt = date
    if let issue = question.answerSpec.evaluate(answer) {
      state.status = .issue
      state.issue = issue
    } else {
      state.status = .matched
      state.issue = nil
    }
    states[questionID] = state
  }

  /// Current problems in exactly the order authored by the Recipe.
  public func issueSnapshots() -> [QuestionRuntimeSnapshot] {
    snapshots().filter { $0.status == .issue && $0.issue != nil }
  }

  public func firstIssue() -> QuestionRuntimeSnapshot? { issueSnapshots().first }

  public func snapshots() -> [QuestionRuntimeSnapshot] {
    questions.map { question in
      let state = states[question.id] ?? State()
      return QuestionRuntimeSnapshot(
        id: question.id,
        title: question.title,
        status: state.status,
        answer: state.answer,
        issue: state.issue,
        lastEvaluatedAt: state.lastEvaluatedAt)
    }
  }

  public var activeCount: Int { states.values.filter { $0.status != .skipped }.count }
  public var skippedCount: Int { states.values.filter { $0.status == .skipped }.count }
  public var matchedCount: Int { states.values.filter { $0.status == .matched }.count }
}
