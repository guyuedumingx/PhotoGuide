import Foundation

public struct GoalWorkSets: Equatable, Sendable {
  public let guardGoals: Set<GoalID>
  public let focusGoals: Set<GoalID>
  public let watchGoals: Set<GoalID>
  public let dormantGoals: Set<GoalID>

  public init(
    guardGoals: Set<GoalID> = [],
    focusGoals: Set<GoalID> = [],
    watchGoals: Set<GoalID> = [],
    dormantGoals: Set<GoalID> = []
  ) {
    self.guardGoals = guardGoals
    self.focusGoals = focusGoals
    self.watchGoals = watchGoals
    self.dormantGoals = dormantGoals
  }
}

public struct GoalSetPlanner: Sendable {
  public init() {}

  public func classify(engine: GoalEngine) -> GoalWorkSets {
    var guards = Set<GoalID>()
    var focus = Set<GoalID>()
    var watch = Set<GoalID>()
    var dormant = Set<GoalID>()

    for (id, runtime) in engine.states where runtime.policy != .skipped {
      guard let definition = engine.definitions[id] else { continue }
      if definition.constraint == .hard { guards.insert(id) }

      switch runtime.state {
      case .active, .drifted:
        if definition.constraint == .soft { watch.insert(id) } else { focus.insert(id) }
      case .satisfied:
        watch.insert(id)
      case .unknown:
        if definition.constraint == .hard { guards.insert(id) } else { focus.insert(id) }
      case .inactive, .unresolved, .blocked:
        dormant.insert(id)
      }
    }

    return GoalWorkSets(
      guardGoals: guards,
      focusGoals: focus,
      watchGoals: watch,
      dormantGoals: dormant
    )
  }

  public func priority(
    of id: GoalID,
    engine: GoalEngine,
    goalGroups: [GoalGroupDefinition] = []
  ) -> Double {
    guard let definition = engine.definitions[id], let runtime = engine.states[id] else { return 0 }
    if runtime.policy == .skipped { return 0 }

    let classWeight: Double =
      switch definition.constraint {
      case .hard: 3.0
      case .core: 2.0
      case .soft: 0.65
      }
    let policyWeight = runtime.policy == .deprioritized ? 0.35 : 1.0
    let severity = max(0.05, 1 - (runtime.score ?? 0.5))
    let regressionBoost = runtime.state == .drifted ? 1.35 : 1.0
    let evidenceWeight = runtime.state == .unknown ? 0.35 : max(0.4, runtime.confidence ?? 0.6)
    let groupMultiplier = GoalGroupEvaluator().priorityMultiplier(
      for: id, groups: goalGroups, engine: engine)
    return classWeight * definition.importance * policyWeight * severity * regressionBoost
      * evidenceWeight * groupMultiplier
  }
}
