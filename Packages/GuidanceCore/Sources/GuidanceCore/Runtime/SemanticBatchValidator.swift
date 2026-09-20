import Foundation

public enum SemanticBatchValidationRule: String, Codable, Sendable {
  case unsolicitedSlot
  case duplicateSlot
  case wrongEvaluator
  case wrongFrame
  case wrongBindingVersion
  case wrongSceneRevision
  case invalidObservation
}

public struct SemanticBatchValidationIssue: Codable, Equatable, Sendable {
  public let rule: SemanticBatchValidationRule
  public let message: String

  public init(rule: SemanticBatchValidationRule, message: String) {
    self.rule = rule
    self.message = message
  }
}

public struct SemanticBatchValidationResult: Sendable {
  public let accepted: [Observation]
  public let issues: [SemanticBatchValidationIssue]

  public init(accepted: [Observation], issues: [SemanticBatchValidationIssue]) {
    self.accepted = accepted
    self.issues = issues
  }
}

/// Strict allow-list for remote semantic responses. A remote evaluator may only
/// answer the slots that were requested for the exact scene/binding context.
/// Extra model output is ignored rather than being allowed to steer the planner.
public struct SemanticBatchValidator: Sendable {
  public init() {}

  public func validate(
    observations: [Observation],
    expectedSlots: [EvaluationSlot],
    expectedEvaluator: EvaluatorID = EvaluatorID("djev.semantic"),
    frameID: Int,
    bindingVersion: Int,
    sceneRevision: Int,
    registry: GuidanceRegistry
  ) -> SemanticBatchValidationResult {
    let expected = Set(
      expectedSlots.map { SemanticSlotKey(dimension: $0.dimension, binding: $0.binding) })
    var seen = Set<SemanticSlotKey>()
    var accepted = [Observation]()
    var issues = [SemanticBatchValidationIssue]()
    let observationValidator = ObservationValidator()

    for observation in observations {
      let key = SemanticSlotKey(dimension: observation.dimension, binding: observation.binding)
      var rejected = false

      if !expected.contains(key) {
        issues.append(
          .init(
            rule: .unsolicitedSlot,
            message: "\(observation.dimension.rawValue) was not requested"
          ))
        rejected = true
      }
      if seen.contains(key) {
        issues.append(
          .init(
            rule: .duplicateSlot,
            message: "Duplicate semantic observation for \(observation.dimension.rawValue)"
          ))
        rejected = true
      }
      if observation.evaluator != expectedEvaluator {
        issues.append(
          .init(
            rule: .wrongEvaluator,
            message: "Expected \(expectedEvaluator.rawValue), got \(observation.evaluator.rawValue)"
          ))
        rejected = true
      }
      if observation.frameID != frameID {
        issues.append(.init(rule: .wrongFrame, message: "Unexpected semantic frame"))
        rejected = true
      }
      if observation.bindingVersion != bindingVersion {
        issues.append(
          .init(rule: .wrongBindingVersion, message: "Binding changed during semantic evaluation"))
        rejected = true
      }
      if observation.sceneRevision != sceneRevision {
        issues.append(
          .init(rule: .wrongSceneRevision, message: "Scene changed during semantic evaluation"))
        rejected = true
      }

      let contractIssues = observationValidator.validate(observation, registry: registry)
      if contractIssues.contains(where: { $0.severity == .error }) {
        issues.append(
          .init(
            rule: .invalidObservation,
            message: contractIssues.map { $0.rule.rawValue }.joined(separator: ",")
          ))
        rejected = true
      }

      seen.insert(key)
      if !rejected { accepted.append(observation) }
    }

    return .init(accepted: accepted, issues: issues)
  }
}

private struct SemanticSlotKey: Hashable {
  let dimension: DimensionID
  let binding: Binding
}
