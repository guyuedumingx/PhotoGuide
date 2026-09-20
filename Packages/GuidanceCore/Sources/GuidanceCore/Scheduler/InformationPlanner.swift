import Foundation

public struct InformationValueEstimate: Equatable, Sendable {
  public let actionID: ActionID
  public let expectedInformationValue: Double
  public let executionCost: Double
  public let netValue: Double

  public init(actionID: ActionID, expectedInformationValue: Double, executionCost: Double) {
    self.actionID = actionID
    self.expectedInformationValue = expectedInformationValue
    self.executionCost = executionCost
    self.netValue = expectedInformationValue - executionCost
  }
}

/// Selects an explicit information-seeking Action when observing first is more
/// valuable than immediately changing the scene. HOLD / WAIT / SELECT_ANCHOR
/// are ordinary Actions; the distinction comes from declared informationEffects.
public struct InformationPlanner: Sendable {
  public var minimumNetValue = 0.08
  public var unknownResolutionBonus = 0.75
  public var dirtyEvidenceBonus = 0.18

  public init() {}

  public func bestAction(
    for goals: Set<GoalID>,
    engine: GoalEngine,
    planner: ActionPlanner,
    actions: [ActionDefinition],
    goalGroups: [GoalGroupDefinition] = []
  ) -> (action: ActionDefinition, estimate: InformationValueEstimate)? {
    let candidates = actions.filter {
      $0.isInformationSeeking
        && !$0.informationGoals.isDisjoint(with: goals)
        && planner.feasible($0, engine: engine)
    }

    let ranked = candidates.compactMap { action -> (ActionDefinition, InformationValueEstimate)? in
      let estimate = value(
        of: action, requestedGoals: goals, engine: engine, planner: planner, goalGroups: goalGroups)
      guard estimate.netValue >= minimumNetValue else { return nil }
      return (action, estimate)
    }.sorted {
      if $0.1.netValue == $1.1.netValue { return $0.0.id.rawValue < $1.0.id.rawValue }
      return $0.1.netValue > $1.1.netValue
    }
    return ranked.first
  }

  public func value(
    of action: ActionDefinition,
    requestedGoals: Set<GoalID>,
    engine: GoalEngine,
    planner: ActionPlanner,
    goalGroups: [GoalGroupDefinition] = []
  ) -> InformationValueEstimate {
    var informationValue = 0.0
    let goalPlanner = GoalSetPlanner()

    for effect in action.informationEffects where requestedGoals.contains(effect.goal) {
      if engine.observation(for: effect.goal) == nil,
        action.operation == .hold || action.operation == .wait
      {
        continue
      }
      guard let definition = engine.definitions[effect.goal],
        let runtime = engine.states[effect.goal],
        runtime.policy != .skipped
      else { continue }

      // Use decision criticality without the normal UNKNOWN evidence discount:
      // the whole point of an information action is to reduce that uncertainty.
      let classWeight: Double =
        switch definition.constraint {
        case .hard: 3.2
        case .core: 1.9
        case .soft: 0.55
        }
      let ordinaryPriority = goalPlanner.priority(
        of: effect.goal, engine: engine, goalGroups: goalGroups)
      let criticality = max(ordinaryPriority, classWeight * definition.importance * 0.45)

      let confidence = runtime.confidence ?? 0
      var epistemicNeed = max(0, 1 - confidence)
      switch runtime.state {
      case .unknown, .unresolved, .inactive:
        epistemicNeed = 1
      case .active, .drifted, .satisfied, .blocked:
        break
      }
      if runtime.dirty { epistemicNeed = min(1, epistemicNeed + dirtyEvidenceBonus) }

      let confidenceValue = effect.confidenceGain * epistemicNeed
      let resolutionValue: Double
      switch runtime.state {
      case .unknown, .unresolved, .inactive:
        resolutionValue = effect.resolutionProbability * unknownResolutionBonus
      default:
        resolutionValue = 0
      }
      informationValue += criticality * (confidenceValue + resolutionValue)
    }

    let learnedPenalty = planner.memory.effectModel.uncertaintyPenalty(for: action)
    let safetyCost = action.safety == .contextDependent ? 0.12 : 0
    let executionCost =
      action.burden + action.risk + action.uncertainty + learnedPenalty + safetyCost
    return InformationValueEstimate(
      actionID: action.id,
      expectedInformationValue: informationValue,
      executionCost: executionCost
    )
  }
}
