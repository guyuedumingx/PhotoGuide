import Foundation

public enum ActionPlanState: String, Codable, Sendable {
  case proposed
  case executing
  case completed
  case cancelled
  case failed
  case superseded
}

/// A short, interruptible horizon of actions. It is not a new domain primitive:
/// it is a runtime composition of existing Action definitions.
public struct ActionPlanDefinition: Codable, Equatable, Sendable {
  public let id: ActionPlanID
  public let steps: [ActionDefinition]
  public let expectedUtility: Double
  public let utilityUncertainty: Double
  public let confidenceAdjustedUtility: Double
  /// CORE/SOFT goals that may temporarily regress between steps but are
  /// expected to recover before the plan completes. HARD and locked goals are
  /// never allowed here.
  public let temporarilyRelaxedGoals: Set<GoalID>

  public init(
    id: ActionPlanID,
    steps: [ActionDefinition],
    expectedUtility: Double,
    utilityUncertainty: Double = 0,
    confidenceAdjustedUtility: Double? = nil,
    temporarilyRelaxedGoals: Set<GoalID> = []
  ) {
    self.id = id
    self.steps = steps
    self.expectedUtility = expectedUtility.isFinite ? expectedUtility : -.infinity
    self.utilityUncertainty = utilityUncertainty.isFinite ? min(max(utilityUncertainty, 0), 1) : 1
    if let confidenceAdjustedUtility, confidenceAdjustedUtility.isFinite {
      self.confidenceAdjustedUtility = confidenceAdjustedUtility
    } else {
      self.confidenceAdjustedUtility = self.expectedUtility - self.utilityUncertainty
    }
    self.temporarilyRelaxedGoals = temporarilyRelaxedGoals
  }
}

public struct ActionPlanRuntime: Codable, Equatable, Sendable {
  public let definition: ActionPlanDefinition
  public var state: ActionPlanState
  /// Index of the step currently being proposed/executed. After successful
  /// verification it advances to the next step.
  public var stepIndex: Int

  public init(_ definition: ActionPlanDefinition) {
    self.definition = definition
    state = .proposed
    stepIndex = 0
  }

  public var currentStep: ActionDefinition? {
    guard definition.steps.indices.contains(stepIndex) else { return nil }
    return definition.steps[stepIndex]
  }

  public var isLastStep: Bool {
    stepIndex == definition.steps.count - 1
  }
}
