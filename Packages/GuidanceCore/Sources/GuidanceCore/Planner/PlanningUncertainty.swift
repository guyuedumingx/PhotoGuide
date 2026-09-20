import Foundation

public struct UtilityDistribution: Equatable, Sendable {
  public let mean: Double
  public let uncertainty: Double
  public let confidenceAdjusted: Double

  public init(mean: Double, uncertainty: Double, riskAversion: Double) {
    self.mean = mean.isFinite ? mean : -.infinity
    self.uncertainty = uncertainty.isFinite ? min(max(uncertainty, 0), 1) : 1
    self.confidenceAdjusted = self.mean - max(0, riskAversion) * self.uncertainty
  }
}

/// Lightweight uncertainty propagation for a short live-camera plan. It does
/// not pretend that Action effects are fully independent probabilities; a
/// correlation floor prevents long plans from looking artificially certain.
public struct PlanningUncertaintyModel: Sendable {
  public var riskAversion = 0.85
  public var correlationFloor = 0.22
  public var perAdditionalStepFloor = 0.04

  public init() {}

  public func actionUncertainty(_ action: ActionDefinition, planner: ActionPlanner) -> Double {
    let learned = planner.memory.effectModel.uncertaintyPenalty(for: action)
    let safety = action.safety == .contextDependent ? 0.10 : 0
    return min(
      1, sqrt(action.uncertainty * action.uncertainty + learned * learned + safety * safety))
  }

  public func sequenceUncertainty(_ actions: [ActionDefinition], planner: ActionPlanner) -> Double {
    guard !actions.isEmpty else { return 0 }
    let values = actions.map { actionUncertainty($0, planner: planner) }
    let independentVariance = values.reduce(0.0) { $0 + $1 * $1 }
    let pairCorrelation = values.enumerated().reduce(0.0) { total, left in
      total
        + values.dropFirst(left.offset + 1).reduce(0.0) {
          $0 + 2 * correlationFloor * left.element * $1
        }
    }
    let horizonFloor = Double(max(0, actions.count - 1)) * perAdditionalStepFloor
    return min(1, sqrt(max(0, independentVariance + pairCorrelation)) + horizonFloor)
  }

  public func estimate(meanUtility: Double, actions: [ActionDefinition], planner: ActionPlanner)
    -> UtilityDistribution
  {
    UtilityDistribution(
      mean: meanUtility,
      uncertainty: sequenceUncertainty(actions, planner: planner),
      riskAversion: riskAversion
    )
  }
}
