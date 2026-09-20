import Foundation

public enum ObservationValidationRule: String, Codable, Sendable {
  case unknownDimension
  case unknownEvaluator
  case evaluatorDoesNotSupportDimension
  case valueTypeMismatch
  case valueOutsideDimensionSpace
  case bindingScopeMismatch
  case invalidConfidence
  case invalidFrameID
  case invalidContextRevision
  case invalidDistribution
  case unexpectedDistribution
}

public struct ObservationValidationIssue: Codable, Equatable, Sendable {
  public let rule: ObservationValidationRule
  public let severity: ValidationSeverity
  public let message: String

  public init(
    rule: ObservationValidationRule,
    severity: ValidationSeverity = .error,
    message: String
  ) {
    self.rule = rule
    self.severity = severity
    self.message = message
  }
}

/// Runtime contract gate for evaluator output. Recipe validation protects the
/// static graph; this validator protects the live controller from malformed or
/// misrouted observations returned by Vision, telemetry or remote semantics.
public struct ObservationValidator: Sendable {
  public init() {}

  public func validate(
    _ observation: Observation,
    registry: GuidanceRegistry
  ) -> [ObservationValidationIssue] {
    var issues = [ObservationValidationIssue]()

    guard let dimension = registry.dimensions[observation.dimension] else {
      return [
        .init(
          rule: .unknownDimension,
          message: "Unknown dimension: \(observation.dimension.rawValue)"
        )
      ]
    }

    if !value(observation.value, matches: dimension.valueType) {
      issues.append(
        .init(
          rule: .valueTypeMismatch,
          message: "\(observation.dimension.rawValue) expects \(dimension.valueType.rawValue)"
        ))
    } else if let valueSpace = dimension.valueSpace, !valueSpace.contains(observation.value) {
      issues.append(
        .init(
          rule: .valueOutsideDimensionSpace,
          message: "Value is outside the declared space for \(observation.dimension.rawValue)"
        ))
    }

    if !binding(observation.binding, matches: dimension.scope) {
      issues.append(
        .init(
          rule: .bindingScopeMismatch,
          message: "\(observation.dimension.rawValue) expects \(dimension.scope.rawValue) binding"
        ))
    }

    if !observation.confidence.isFinite || !(0...1).contains(observation.confidence) {
      issues.append(
        .init(
          rule: .invalidConfidence,
          message: "Confidence must be finite and in 0...1"
        ))
    }

    if observation.frameID < 0 {
      issues.append(.init(rule: .invalidFrameID, message: "frameID must be non-negative"))
    }
    if observation.bindingVersion < 0 || observation.sceneRevision < 0 {
      issues.append(
        .init(
          rule: .invalidContextRevision,
          message: "bindingVersion and sceneRevision must be non-negative"
        ))
    }

    if observation.evaluator != EvaluatorID("core.fusion") {
      guard let evaluator = registry.evaluators[observation.evaluator] else {
        issues.append(
          .init(
            rule: .unknownEvaluator,
            message: "Unknown evaluator: \(observation.evaluator.rawValue)"
          ))
        return issues
      }

      if !evaluator.supportedDimensions.isEmpty,
        !evaluator.supportedDimensions.contains(observation.dimension)
      {
        issues.append(
          .init(
            rule: .evaluatorDoesNotSupportDimension,
            message:
              "\(observation.evaluator.rawValue) cannot evaluate \(observation.dimension.rawValue)"
          ))
      }

      if observation.distribution != nil && !evaluator.supportsDistribution {
        issues.append(
          .init(
            rule: .unexpectedDistribution,
            severity: .warning,
            message: "\(observation.evaluator.rawValue) declared no distribution support"
          ))
      }
    }

    if let distribution = observation.distribution {
      if dimension.valueType != .ordinal {
        issues.append(
          .init(
            rule: .unexpectedDistribution,
            message: "Distributions are currently supported only for ordinal dimensions"
          ))
      }
      let entriesAreValid =
        !distribution.isEmpty
        && distribution.allSatisfy { key, probability in
          guard let ordinal = Int(key), probability.isFinite, probability >= 0 else { return false }
          if case .ordinal(let min, let max)? = dimension.valueSpace {
            return ordinal >= min && ordinal <= max
          }
          return true
        }
      let total = distribution.values.reduce(0, +)
      if !entriesAreValid || !total.isFinite || total <= 0 {
        issues.append(
          .init(
            rule: .invalidDistribution,
            message: "Distribution must contain finite, non-negative ordinal mass"
          ))
      }
    }

    return issues
  }

  public func accepts(_ observation: Observation, registry: GuidanceRegistry) -> Bool {
    !validate(observation, registry: registry).contains { $0.severity == .error }
  }

  private func value(_ value: DimensionValue, matches type: DimensionValueType) -> Bool {
    switch (value, type) {
    case (.continuous(let value), .continuous): value.isFinite
    case (.ordinal, .ordinal), (.categorical, .categorical), (.boolean, .boolean): true
    default: false
    }
  }

  private func binding(_ binding: Binding, matches scope: DimensionScope) -> Bool {
    switch (binding, scope) {
    case (.node, .node), (.relation, .relation), (.frame, .frame), (.capture, .capture): true
    default: false
    }
  }
}
