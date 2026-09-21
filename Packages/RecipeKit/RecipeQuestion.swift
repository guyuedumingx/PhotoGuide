import Foundation
import GuidanceCore

public enum RecipeQuestionType: String, Codable, CaseIterable, Sendable {
  case choice
  case score
  case boolean
}

public struct RecipeReferenceDTO: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let mimeType: String
  /// Portable Recipe v1 embeds small reference images so imports/marketplace
  /// recipes remain self-contained. A future package format can move these bytes
  /// to files without changing the runtime VisualReference contract.
  public let imageBase64: String

  public init(id: String, mimeType: String = "image/jpeg", imageBase64: String) {
    self.id = id
    self.mimeType = mimeType
    self.imageBase64 = imageBase64
  }

  public init(id: String, mimeType: String = "image/jpeg", imageData: Data) {
    self.init(id: id, mimeType: mimeType, imageBase64: imageData.base64EncodedString())
  }

  public var imageData: Data? { Data(base64Encoded: imageBase64) }
}

public struct RecipeChoiceOptionDTO: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let label: String
  /// Nil means this option matches the Recipe target.
  public let issue: String?
  public init(id: String, label: String, issue: String? = nil) {
    self.id = id
    self.label = label
    self.issue = issue
  }
}

public struct RecipeQuestionDTO: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let prompt: String
  public let type: RecipeQuestionType
  public let choices: [RecipeChoiceOptionDTO]?

  public let scoreMin: Double?
  public let scoreMax: Double?
  public let expectedMin: Double?
  public let expectedMax: Double?
  public let belowIssue: String?
  public let aboveIssue: String?

  public let expectedBoolean: Bool?
  public let mismatchIssue: String?

  public init(
    id: String,
    title: String,
    prompt: String,
    type: RecipeQuestionType,
    choices: [RecipeChoiceOptionDTO]? = nil,
    scoreMin: Double? = nil,
    scoreMax: Double? = nil,
    expectedMin: Double? = nil,
    expectedMax: Double? = nil,
    belowIssue: String? = nil,
    aboveIssue: String? = nil,
    expectedBoolean: Bool? = nil,
    mismatchIssue: String? = nil
  ) {
    self.id = id
    self.title = title
    self.prompt = prompt
    self.type = type
    self.choices = choices
    self.scoreMin = scoreMin
    self.scoreMax = scoreMax
    self.expectedMin = expectedMin
    self.expectedMax = expectedMax
    self.belowIssue = belowIssue
    self.aboveIssue = aboveIssue
    self.expectedBoolean = expectedBoolean
    self.mismatchIssue = mismatchIssue
  }

  public static func choice(
    id: String,
    title: String,
    prompt: String,
    options: [RecipeChoiceOptionDTO]
  ) -> Self {
    .init(id: id, title: title, prompt: prompt, type: .choice, choices: options)
  }

  public static func score(
    id: String,
    title: String,
    prompt: String,
    range: ClosedRange<Double> = 0...100,
    expected: ClosedRange<Double>,
    belowIssue: String? = nil,
    aboveIssue: String? = nil
  ) -> Self {
    .init(
      id: id, title: title, prompt: prompt, type: .score,
      scoreMin: range.lowerBound, scoreMax: range.upperBound,
      expectedMin: expected.lowerBound, expectedMax: expected.upperBound,
      belowIssue: belowIssue, aboveIssue: aboveIssue)
  }

  public static func boolean(
    id: String,
    title: String,
    prompt: String,
    expected: Bool,
    mismatchIssue: String
  ) -> Self {
    .init(
      id: id, title: title, prompt: prompt, type: .boolean,
      expectedBoolean: expected, mismatchIssue: mismatchIssue)
  }
}

public enum RecipeQuestionValidationError: Error, Equatable, Sendable {
  case emptyID
  case emptyPrompt(String)
  case invalidChoice(String)
  case invalidScore(String)
  case invalidBoolean(String)
}

public extension RecipeQuestionDTO {
  func validate() -> RecipeQuestionValidationError? {
    if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyID }
    if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyPrompt(id) }

    switch type {
    case .choice:
      guard let choices, choices.count >= 2,
        Set(choices.map(\.id)).count == choices.count,
        choices.contains(where: { $0.issue == nil })
      else { return .invalidChoice(id) }
      for choice in choices {
        if choice.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .invalidChoice(id) }
      }
    case .score:
      guard let min = scoreMin, let max = scoreMax,
        let low = expectedMin, let high = expectedMax,
        [min, max, low, high].allSatisfy(\.isFinite),
        min < max, min <= low, low <= high, high <= max,
        (low == min || !(belowIssue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
        (high == max || !(aboveIssue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      else { return .invalidScore(id) }
    case .boolean:
      guard expectedBoolean != nil,
        let mismatchIssue, !mismatchIssue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return .invalidBoolean(id) }
    }
    return nil
  }

  var compiled: VisualQuestion? {
    guard validate() == nil else { return nil }
    let spec: JudgeAnswerSpec
    switch type {
    case .choice:
      spec = .choice(options: (choices ?? []).map {
        JudgeChoiceOption(id: $0.id, label: $0.label, issue: $0.issue)
      })
    case .score:
      spec = .score(
        range: scoreMin!...scoreMax!,
        expected: expectedMin!...expectedMax!,
        belowIssue: belowIssue,
        aboveIssue: aboveIssue)
    case .boolean:
      spec = .boolean(expected: expectedBoolean!, mismatchIssue: mismatchIssue!)
    }
    return VisualQuestion(id: id, title: title, prompt: prompt, answerSpec: spec)
  }
}

public extension RecipeDTO {
  var resolvedVisualReferences: [VisualReference] {
    (references ?? []).compactMap { item in
      guard let data = item.imageData, !data.isEmpty else { return nil }
      return VisualReference(id: item.id, mimeType: item.mimeType, imagePayload: data)
    }
  }

  var resolvedVisualQuestions: [VisualQuestion] {
    if let questions, !questions.isEmpty {
      return questions.compactMap(\.compiled)
    }

    // Migration-only fallback for older v0.8 Recipes. It lets old files open,
    // but new/custom Recipes are authored directly as bounded questions.
    return resolvedCritic.dimensions.map { dimension in
      VisualQuestion(
        id: "legacy.\(dimension.id)",
        title: dimension.name,
        prompt: "Compare the current frame with the Recipe references for \(dimension.name). Is it close enough to the intended look?",
        answerSpec: .boolean(expected: true, mismatchIssue: "\(dimension.name) 与参考目标有差距"))
    }
  }

  var questionValidationErrors: [RecipeQuestionValidationError] {
    (questions ?? []).compactMap { $0.validate() }
  }
}

public extension RecipeFactory {
  static func questionRecipe(
    id: String,
    title: String,
    subtitle: String,
    domain: RecipeDomain = .general,
    icon: String = "viewfinder",
    tags: [String] = [],
    references: [RecipeReferenceDTO],
    questions: [RecipeQuestionDTO]
  ) -> RecipeDTO {
    RecipeDTO(
      id: id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "user.\(UUID().uuidString.lowercased())" : id,
      title: title,
      subtitle: subtitle,
      perception: .init(subjectStrategy: .scene, anchorStrategy: RecipeAnchorStrategy.none, allowsManualSubjectSelection: false),
      presentation: .init(domain: domain, icon: icon, tags: tags),
      references: references,
      questions: questions,
      critic: nil)
  }

  static var defaultQuestions: [RecipeQuestionDTO] {
    [
      .choice(
        id: "angle", title: "拍摄视角",
        prompt: "当前拍摄视角与参考图相比？",
        options: [
          .init(id: "too_high", label: "太高", issue: "拍摄角度比参考图偏高"),
          .init(id: "matched", label: "接近参考图"),
          .init(id: "too_low", label: "太低", issue: "拍摄角度比参考图偏低"),
        ]),
      .choice(
        id: "subject_scale", title: "主体大小",
        prompt: "当前主体在画面中的占比与参考图相比？",
        options: [
          .init(id: "too_small", label: "偏小", issue: "主体比参考图偏小"),
          .init(id: "matched", label: "接近参考图"),
          .init(id: "too_large", label: "偏大", issue: "主体比参考图偏大"),
        ]),
      .choice(
        id: "background_blur", title: "背景虚化",
        prompt: "当前背景虚化程度与参考图相比？",
        options: [
          .init(id: "too_blurry", label: "虚化更强", issue: "背景虚化比参考图更强"),
          .init(id: "matched", label: "接近参考图"),
          .init(id: "too_clear", label: "虚化更弱", issue: "背景比参考图更清楚"),
        ]),
      .choice(
        id: "brightness", title: "画面亮度",
        prompt: "当前画面亮度与参考图相比？",
        options: [
          .init(id: "too_dark", label: "偏暗", issue: "画面比参考图偏暗"),
          .init(id: "matched", label: "接近参考图"),
          .init(id: "too_bright", label: "偏亮", issue: "画面比参考图偏亮"),
        ]),
      .score(
        id: "overall_similarity", title: "整体相似度",
        prompt: "当前画面与参考图整体视觉效果的相似度是多少？",
        expected: 82...100, belowIssue: "当前画面与参考风格还有明显差距")
    ]
  }
}
