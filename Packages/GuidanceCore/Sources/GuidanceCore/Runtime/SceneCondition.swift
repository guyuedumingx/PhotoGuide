import Foundation

/// Runtime conditions that can systematically reduce perception quality. These
/// are observations about the sensing context, not photography-quality goals.
public enum SceneCondition: String, Codable, CaseIterable, Sendable {
  case lowLight
  case backlit
  case motionBlur
  case subjectSmall
  case subjectOccluded
  case multiPersonCrowding
  case inputCompression
  case cameraMotion
}

public struct SceneConditionProfile: Codable, Equatable, Sendable {
  public var severities: [SceneCondition: Double]
  public var confidence: Double
  public var frameID: Int?
  public var sceneRevision: Int

  public init(
    severities: [SceneCondition: Double] = [:],
    confidence: Double = 1,
    frameID: Int? = nil,
    sceneRevision: Int = 0
  ) {
    self.severities = severities.mapValues(Self.clamp)
    self.confidence = Self.clamp(confidence)
    self.frameID = frameID
    self.sceneRevision = max(0, sceneRevision)
  }

  public func severity(_ condition: SceneCondition) -> Double {
    severities[condition] ?? 0
  }

  public var isClear: Bool {
    SceneCondition.allCases.allSatisfy { severity($0) < 0.05 }
  }

  public func withContext(frameID: Int? = nil, sceneRevision: Int? = nil) -> SceneConditionProfile {
    SceneConditionProfile(
      severities: severities,
      confidence: confidence,
      frameID: frameID ?? self.frameID,
      sceneRevision: sceneRevision ?? self.sceneRevision
    )
  }

  public func merged(with newer: SceneConditionProfile) -> SceneConditionProfile {
    var values = severities
    for condition in SceneCondition.allCases {
      values[condition] = max(severity(condition), newer.severity(condition))
    }
    return SceneConditionProfile(
      severities: values,
      confidence: max(confidence, newer.confidence),
      frameID: newer.frameID ?? frameID,
      sceneRevision: max(sceneRevision, newer.sceneRevision)
    )
  }

  private static func clamp(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
  }
}

/// Converts scene conditions into a temporary reliability multiplier. The
/// learned reliability model remains session-local history; condition penalties
/// are contextual and therefore must not permanently punish an evaluator.
public struct SceneConditionReliabilityAdjuster: Sendable {
  public var minimumMultiplier = 0.12

  public init() {}

  public func multiplier(
    evaluator: EvaluatorDefinition?,
    dimension: DimensionID,
    profile: SceneConditionProfile?
  ) -> Double {
    guard let evaluator, let profile else { return 1 }
    guard profile.confidence > 0 else { return 1 }

    var multiplier = 1.0
    for condition in SceneCondition.allCases {
      let severity = profile.severity(condition) * profile.confidence
      guard severity > 0 else { continue }
      let sensitivity = sensitivity(
        evaluatorKind: evaluator.kind,
        dimension: dimension,
        condition: condition
      )
      multiplier *= max(0.05, 1 - severity * sensitivity)
    }
    return min(max(multiplier, minimumMultiplier), 1)
  }

  private func sensitivity(
    evaluatorKind: EvaluatorKind,
    dimension: DimensionID,
    condition: SceneCondition
  ) -> Double {
    let base: Double
    switch evaluatorKind {
    case .localVision:
      switch condition {
      case .lowLight: base = 0.35
      case .backlit: base = 0.25
      case .motionBlur: base = 0.65
      case .subjectSmall: base = 0.50
      case .subjectOccluded: base = 0.58
      case .multiPersonCrowding: base = 0.45
      case .inputCompression: base = 0.10
      case .cameraMotion: base = 0.40
      }
    case .semanticRemote:
      switch condition {
      case .lowLight: base = 0.28
      case .backlit: base = 0.18
      case .motionBlur: base = 0.45
      case .subjectSmall: base = 0.42
      case .subjectOccluded: base = 0.55
      case .multiPersonCrowding: base = 0.36
      case .inputCompression: base = 0.48
      case .cameraMotion: base = 0.18
      }
    case .temporal:
      base = condition == .cameraMotion || condition == .motionBlur ? 0.35 : 0.10
    case .localTelemetry:
      base = 0.02
    case .fusion:
      base = 0
    case .other:
      base = 0.20
    }

    let id = dimension.rawValue
    var dimensionBoost = 0.0
    if id.contains("body_orientation") || id.contains("pose") {
      if condition == .subjectOccluded || condition == .subjectSmall || condition == .motionBlur {
        dimensionBoost += 0.25
      }
    }
    if id.contains("relative_scale") || id.contains("visual_balance") {
      if condition == .subjectSmall || condition == .inputCompression || condition == .backlit {
        dimensionBoost += 0.18
      }
    }
    if id.contains("exists") || id.contains("visibility") {
      if condition == .subjectOccluded || condition == .multiPersonCrowding {
        dimensionBoost += 0.22
      }
    }
    return min(0.95, base + dimensionBoost)
  }
}
