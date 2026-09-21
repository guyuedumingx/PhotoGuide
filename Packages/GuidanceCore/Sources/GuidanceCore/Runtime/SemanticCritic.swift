import Foundation

/// The model-facing heart of PhotoGuide.
///
/// A Recipe declares *what* photographic qualities matter. A multimodal critic
/// (DJev today, any future low-latency vision-language/system-one model later)
/// scores those qualities from one or more sampled frames and returns concise,
/// professional advice. The core deliberately knows nothing about people,
/// flowers, food, landscapes, or any other subject class.

public enum SemanticCriticContract {
  /// Increment only for a breaking network-semantic change. Additive fields stay
  /// on the same version so older/newer evaluator implementations can coexist.
  public static let version = 1
}

public struct CriticDimensionSpec: Codable, Equatable, Hashable, Sendable {
  public let id: String
  public let name: String
  public let rubric: String
  public let weight: Double
  public let targetScore: Double
  public let actionability: Double
  /// A required dimension must have a confident assessment and reach its target
  /// before the client can present READY. This is a generic quality gate, not a
  /// subject/category branch.
  public let requiredForReady: Bool
  /// Per-dimension confidence floor used for readiness and weighted coverage.
  public let minimumConfidence: Double

  public init(
    id: String,
    name: String,
    rubric: String,
    weight: Double = 1,
    targetScore: Double = 0.78,
    actionability: Double = 1,
    requiredForReady: Bool = false,
    minimumConfidence: Double = 0.45
  ) {
    self.id = id
    self.name = name
    self.rubric = rubric
    self.weight = Self.unit(weight)
    self.targetScore = Self.unit(targetScore)
    self.actionability = Self.unit(actionability)
    self.requiredForReady = requiredForReady
    self.minimumConfidence = Self.unit(minimumConfidence)
  }

  private static func unit(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
  }
}

public struct CriticProfile: Codable, Equatable, Sendable {
  public let intent: String
  public let dimensions: [CriticDimensionSpec]
  public let adviceStyle: String
  public let preferredSampleCount: Int
  public let minimumSampleSpacing: TimeInterval

  public init(
    intent: String,
    dimensions: [CriticDimensionSpec],
    adviceStyle: String = "Give one concrete, high-impact photography adjustment at a time.",
    preferredSampleCount: Int = 3,
    minimumSampleSpacing: TimeInterval = 0.22
  ) {
    self.intent = intent
    self.dimensions = dimensions
    self.adviceStyle = adviceStyle
    self.preferredSampleCount = min(max(preferredSampleCount, 1), 5)
    self.minimumSampleSpacing = min(max(minimumSampleSpacing, 0), 2)
  }
}

public struct CriticDimensionAssessment: Codable, Equatable, Sendable {
  public let dimensionID: String
  public let score: Double
  public let confidence: Double
  public let rationale: String
  public let evidenceFrameIDs: [Int]

  public init(
    dimensionID: String,
    score: Double,
    confidence: Double,
    rationale: String = "",
    evidenceFrameIDs: [Int] = []
  ) {
    self.dimensionID = dimensionID
    self.score = Self.unit(score)
    self.confidence = Self.unit(confidence)
    self.rationale = rationale
    self.evidenceFrameIDs = evidenceFrameIDs
  }

  private static func unit(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
  }
}

public enum CriticAdviceKind: String, Codable, Equatable, Sendable {
  case composition
  case camera
  case lighting
  case subject
  case scene
  case timing
  case wait
  case capture
  case other
}

public struct CriticAdvice: Codable, Equatable, Sendable {
  public let dimensionID: String?
  public let kind: CriticAdviceKind
  public let title: String
  public let detail: String
  public let confidence: Double
  public let requiresPhysicalMovement: Bool

  public init(
    dimensionID: String? = nil,
    kind: CriticAdviceKind = .other,
    title: String,
    detail: String,
    confidence: Double = 0.8,
    requiresPhysicalMovement: Bool = false
  ) {
    self.dimensionID = dimensionID
    self.kind = kind
    self.title = title
    self.detail = detail
    self.confidence = min(max(confidence.isFinite ? confidence : 0, 0), 1)
    self.requiresPhysicalMovement = requiresPhysicalMovement
  }
}

public struct SemanticCritique: Codable, Equatable, Sendable {
  public let assessments: [CriticDimensionAssessment]
  public let advice: [CriticAdvice]
  public let overallScore: Double?
  public let captureReady: Bool?
  public let modelID: String?

  public init(
    assessments: [CriticDimensionAssessment],
    advice: [CriticAdvice] = [],
    overallScore: Double? = nil,
    captureReady: Bool? = nil,
    modelID: String? = nil
  ) {
    self.assessments = assessments
    self.advice = advice
    self.overallScore = overallScore.map { min(max($0.isFinite ? $0 : 0, 0), 1) }
    self.captureReady = captureReady
    self.modelID = modelID
  }
}

public struct CriticImageSample: Equatable, Sendable {
  public let frameID: Int
  public let timestamp: TimeInterval
  public let imagePayload: Data

  public init(
    frameID: Int,
    timestamp: TimeInterval = Date().timeIntervalSince1970,
    imagePayload: Data
  ) {
    self.frameID = frameID
    self.timestamp = timestamp
    self.imagePayload = imagePayload
  }
}

/// The only model execution contract required by the PhotoGuide product core.
///
/// Implementations may call DJev/JEV today or any future low-latency multimodal
/// critic. They receive only the Recipe quality profile plus sampled images. No
/// Goal graph, detector binding, subject class or local Vision state is required.
public protocol MultimodalCritic: Sendable {
  func critique(
    profile: CriticProfile,
    samples: [CriticImageSample],
    locale: String
  ) async throws -> SemanticCritique
}

public enum SemanticCritiqueIssue: Equatable, Sendable {
  case duplicateDimension(String)
  case duplicateProfileDimension(String)
  case unknownDimension(String)
  case missingDimension(String)
  case lowConfidence(String)
  case missingRequiredDimension(String)
  case lowCoverage
  case lowWeightedCoverage
}

public struct SemanticCritiqueValidation: Equatable, Sendable {
  public let critique: SemanticCritique
  public let issues: [SemanticCritiqueIssue]
  public let coverage: Double
  public let weightedCoverage: Double
  public let requiredDimensionsSatisfied: Bool
  public let isUsable: Bool

  public init(
    critique: SemanticCritique,
    issues: [SemanticCritiqueIssue],
    coverage: Double,
    weightedCoverage: Double,
    requiredDimensionsSatisfied: Bool,
    isUsable: Bool
  ) {
    self.critique = critique
    self.issues = issues
    self.coverage = coverage
    self.weightedCoverage = weightedCoverage
    self.requiredDimensionsSatisfied = requiredDimensionsSatisfied
    self.isUsable = isUsable
  }
}

/// Small, domain-agnostic contract validation. It intentionally does not try to
/// second-guess the model's photographic judgment; it only guarantees that the
/// response matches the Recipe's requested dimensions.
public struct SemanticCritiqueValidator: Sendable {
  public var minimumCoverage: Double = 0.60
  public var minimumWeightedCoverage: Double = 0.70

  public init() {}

  public func validate(_ critique: SemanticCritique, against profile: CriticProfile)
    -> SemanticCritiqueValidation
  {
    var specs = [String: CriticDimensionSpec]()
    var issues = [SemanticCritiqueIssue]()
    for spec in profile.dimensions {
      if specs[spec.id] != nil {
        issues.append(.duplicateProfileDimension(spec.id))
      } else {
        specs[spec.id] = spec
      }
    }
    let expected = Set(specs.keys)
    var seen = Set<String>()
    var accepted = [CriticDimensionAssessment]()

    for assessment in critique.assessments {
      guard let spec = specs[assessment.dimensionID] else {
        issues.append(.unknownDimension(assessment.dimensionID))
        continue
      }
      guard seen.insert(assessment.dimensionID).inserted else {
        issues.append(.duplicateDimension(assessment.dimensionID))
        continue
      }
      if assessment.confidence < spec.minimumConfidence {
        issues.append(.lowConfidence(assessment.dimensionID))
      }
      accepted.append(assessment)
    }

    for id in expected.subtracting(seen) {
      issues.append(.missingDimension(id))
      if specs[id]?.requiredForReady == true { issues.append(.missingRequiredDimension(id)) }
    }

    let coverage = expected.isEmpty ? 1 : Double(accepted.count) / Double(expected.count)
    if coverage < minimumCoverage { issues.append(.lowCoverage) }

    let totalWeight = profile.dimensions.reduce(0.0) { $0 + max(0.05, $1.weight) }
    let usableWeight = accepted.reduce(0.0) { partial, assessment in
      guard let spec = specs[assessment.dimensionID], assessment.confidence >= spec.minimumConfidence else {
        return partial
      }
      return partial + max(0.05, spec.weight)
    }
    let weightedCoverage = totalWeight > 0 ? usableWeight / totalWeight : 1
    if weightedCoverage < minimumWeightedCoverage { issues.append(.lowWeightedCoverage) }

    let acceptedByID = Dictionary(uniqueKeysWithValues: accepted.map { ($0.dimensionID, $0) })
    let requiredDimensionsSatisfied = profile.dimensions.filter(\.requiredForReady).allSatisfy { spec in
      guard let assessment = acceptedByID[spec.id] else { return false }
      return assessment.confidence >= spec.minimumConfidence
    }

    let acceptedIDs = Set(accepted.map(\.dimensionID))
    let advice = critique.advice.filter { item in
      item.dimensionID.map { expected.contains($0) && acceptedIDs.contains($0) } ?? true
    }
    let usable = coverage >= minimumCoverage && weightedCoverage >= minimumWeightedCoverage
    return SemanticCritiqueValidation(
      critique: SemanticCritique(
        assessments: accepted,
        advice: advice,
        overallScore: critique.overallScore,
        captureReady: critique.captureReady,
        modelID: critique.modelID),
      issues: issues,
      coverage: coverage,
      weightedCoverage: weightedCoverage,
      requiredDimensionsSatisfied: requiredDimensionsSatisfied,
      isUsable: usable)
  }
}

/// Converts multi-dimensional scores into a stable product decision when the
/// model did not explicitly provide one. Model advice remains first-class.
public struct SemanticCritiqueReducer: Sendable {
  public var minimumAdviceConfidence: Double = 0.55
  public var readyFloor: Double = 0.72

  public init() {}

  public func primaryAdvice(for critique: SemanticCritique, profile: CriticProfile) -> CriticAdvice? {
    if let explicit = critique.advice.first(where: { $0.confidence >= minimumAdviceConfidence }) {
      return explicit
    }

    let specs = Self.dimensionMap(profile.dimensions)
    let weakest = critique.assessments.compactMap { assessment -> (Double, CriticDimensionAssessment, CriticDimensionSpec)? in
      guard let spec = specs[assessment.dimensionID], spec.actionability > 0 else { return nil }
      let deficit = max(0, spec.targetScore - assessment.score)
      let impact = deficit * max(0.05, spec.weight) * max(0.05, spec.actionability) * assessment.confidence
      return (impact, assessment, spec)
    }.max { $0.0 < $1.0 }

    guard let weakest, weakest.0 > 0.015 else { return nil }
    return CriticAdvice(
      dimensionID: weakest.1.dimensionID,
      kind: .other,
      title: weakest.2.name,
      detail: weakest.1.rationale,
      confidence: weakest.1.confidence)
  }

  public func isCaptureReady(_ critique: SemanticCritique, profile: CriticProfile) -> Bool {
    // A model may conservatively veto READY. A positive model flag is treated as
    // a hint, never as permission to bypass missing/weak required dimensions.
    if critique.captureReady == false { return false }
    guard !profile.dimensions.isEmpty else { return false }
    let assessments = Self.assessmentMap(critique.assessments)
    var weighted = 0.0
    var totalWeight = 0.0
    for spec in profile.dimensions {
      guard let assessment = assessments[spec.id], assessment.confidence >= spec.minimumConfidence else {
        if spec.requiredForReady { return false }
        continue
      }
      if spec.requiredForReady && assessment.score < spec.targetScore { return false }
      let weight = max(0.05, spec.weight)
      weighted += assessment.score * weight
      totalWeight += weight
    }
    guard totalWeight > 0 else { return false }
    let computedReady = weighted / totalWeight >= readyFloor
    if critique.captureReady == true { return computedReady }
    return computedReady
  }

  public func overallScore(_ critique: SemanticCritique, profile: CriticProfile) -> Double? {
    if let explicit = critique.overallScore { return explicit }
    let assessments = Self.assessmentMap(critique.assessments)
    var weighted = 0.0
    var totalWeight = 0.0
    for spec in profile.dimensions {
      guard let assessment = assessments[spec.id] else { continue }
      let weight = max(0.05, spec.weight) * max(0.2, assessment.confidence)
      weighted += assessment.score * weight
      totalWeight += weight
    }
    return totalWeight > 0 ? weighted / totalWeight : nil
  }

  private static func dimensionMap(_ dimensions: [CriticDimensionSpec]) -> [String: CriticDimensionSpec] {
    var result = [String: CriticDimensionSpec]()
    for dimension in dimensions where result[dimension.id] == nil { result[dimension.id] = dimension }
    return result
  }

  private static func assessmentMap(_ assessments: [CriticDimensionAssessment]) -> [String: CriticDimensionAssessment] {
    var result = [String: CriticDimensionAssessment]()
    for assessment in assessments where result[assessment.dimensionID] == nil {
      result[assessment.dimensionID] = assessment
    }
    return result
  }
}
