import Foundation

public enum SchedulerDecision: Equatable, Sendable {
  case propose(ActionDefinition)
  case requestEvidence(EvidenceRequest)
  case wait
  case ready
  case readyByUser
  case paused
  case unreachable
  case unknown
}

/// Goal-centric scheduler. HARD goals are guards, CORE goals drive active
/// optimization, SOFT goals are advisory. Capture readiness is evaluated by a
/// non-compensatory policy rather than by requiring every goal to be perfect.
public struct GuidanceScheduler: Sendable {
  public var marginalImprovementThreshold = 0.08
  public var fatigueThreshold = 4
  public var oppositeEffectRecoveryThreshold = 2
  public var oscillationPauseThreshold = 1
  public var readinessPolicy = ReadinessPolicy()
  public var goalSetPlanner = GoalSetPlanner()
  public var reachabilityAnalyzer = ReachabilityAnalyzer()
  public var informationPlanner = InformationPlanner()

  public init() {}

  public func decide(
    engine: GoalEngine,
    planner: ActionPlanner,
    actions: [ActionDefinition],
    goalGroups: [GoalGroupDefinition] = [],
    currentAction: ActionDefinition? = nil,
    userSatisfied: Bool = false
  ) -> SchedulerDecision {
    if planner.needsReobserve { return .wait }

    let relevant = engine.states.filter { $0.value.policy != .skipped }
    if relevant.isEmpty { return .ready }

    let workSets = goalSetPlanner.classify(engine: engine)
    let hardEntries = relevant.filter { engine.definitions[$0.key]?.constraint == .hard }
    let unknownHard = Set(
      hardEntries.compactMap { entry -> GoalID? in
        switch entry.value.state {
        case .unknown, .unresolved, .inactive: return entry.key
        default: return nil
        }
      })
    if !unknownHard.isEmpty {
      if let information = informationPlanner.bestAction(
        for: unknownHard, engine: engine, planner: planner, actions: actions, goalGroups: goalGroups
      ) {
        return .propose(information.action)
      }
      return .requestEvidence(.init(goals: unknownHard, reason: .hardGuardUnknown))
    }

    let readiness = readinessPolicy.assess(engine: engine, goalGroups: goalGroups)
    if userSatisfied, readiness.hardSatisfied { return .readyByUser }

    let blockedCritical = relevant.contains { entry in
      guard let definition = engine.definitions[entry.key], definition.constraint != .soft else {
        return false
      }
      return entry.value.state == .blocked
    }
    if blockedCritical { return .unreachable }

    let reachability = reachabilityAnalyzer.assess(
      engine: engine, planner: planner, actions: actions)

    // Repeated opposite effects mean the controller's local model or the user's
    // interpretation is suspect. Stop issuing motion commands until resumed.
    if planner.memory.oppositeEffects >= oppositeEffectRecoveryThreshold,
      readiness.hardSatisfied
    {
      return .paused
    }
    if planner.memory.oscillationEvents >= oscillationPauseThreshold, readiness.hardSatisfied {
      return .paused
    }
    if planner.memory.fatigue >= fatigueThreshold, readiness.hardSatisfied { return .paused }

    if readiness.automaticReady { return .ready }

    var focusGoals = workSets.focusGoals.filter { id in
      guard let state = engine.states[id] else { return false }
      return state.state == .active || state.state == .drifted
    }

    // HARD failures preempt ordinary CORE optimization. This prevents several
    // moderate CORE gains from numerically outweighing one guard failure.
    let activeHard = Set(focusGoals.filter { engine.definitions[$0]?.constraint == .hard })
    if !activeHard.isEmpty { focusGoals = activeHard }

    if focusGoals.isEmpty {
      let hasUnknownCore = relevant.contains { entry in
        guard engine.definitions[entry.key]?.constraint == .core else { return false }
        return entry.value.state == .unknown || entry.value.state == .unresolved
          || entry.value.state == .inactive
      }
      if hasUnknownCore {
        let unknownCore = Set(
          relevant.compactMap { entry -> GoalID? in
            guard engine.definitions[entry.key]?.constraint == .core else { return nil }
            switch entry.value.state {
            case .unknown, .unresolved, .inactive: return entry.key
            default: return nil
            }
          })
        if let information = informationPlanner.bestAction(
          for: unknownCore, engine: engine, planner: planner, actions: actions,
          goalGroups: goalGroups)
        {
          return .propose(information.action)
        }
        return .requestEvidence(.init(goals: unknownCore, reason: .coreUnknown))
      }
      return readiness.hardSatisfied ? .ready : .unknown
    }

    let candidates = actions.filter { !$0.improvedGoals.isDisjoint(with: focusGoals) }

    // Keep the visible instruction stable while it is still valid. A newly
    // active HARD goal may preempt a CORE instruction.
    if let currentAction,
      planner.feasible(currentAction, engine: engine),
      !currentAction.improvedGoals.isDisjoint(with: focusGoals),
      activeHard.isEmpty || !currentAction.improvedGoals.isDisjoint(with: activeHard),
      planner.utility(currentAction, engine: engine, goalGroups: goalGroups)
        >= marginalImprovementThreshold
    {
      return .propose(currentAction)
    }

    let ranked = planner.rank(candidates, engine: engine, goalGroups: goalGroups)
    guard let first = ranked.first else {
      if !reachability.blockedCriticalGoals.isEmpty {
        return readiness.bestReachableUsable ? .ready : .unreachable
      }
      if !reachability.unknownCriticalGoals.isEmpty {
        if let information = informationPlanner.bestAction(
          for: reachability.unknownCriticalGoals,
          engine: engine,
          planner: planner,
          actions: actions,
          goalGroups: goalGroups
        ) {
          return .propose(information.action)
        }
        return .requestEvidence(
          .init(
            goals: reachability.unknownCriticalGoals, reason: .staleOrMissing))
      }
      return readiness.bestReachableUsable ? .ready : .unreachable
    }

    if planner.utility(first, engine: engine, goalGroups: goalGroups) < marginalImprovementThreshold
    {
      return readiness.bestReachableUsable ? .ready : .unreachable
    }
    return .propose(first)
  }
}
