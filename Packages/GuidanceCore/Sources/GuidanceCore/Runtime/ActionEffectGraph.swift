import Foundation

/// Read-only causal index derived from Action declarations. It makes shared
/// causes and side effects explicit without teaching the kernel photography-
/// specific semantics.
public struct ActionEffectGraph: Sendable {
  private let actionsByGoal: [GoalID: [ActionDefinition]]
  private let effectsByAction: [ActionID: [ActionEffect]]

  public init(actions: [ActionDefinition]) {
    var byGoal: [GoalID: [ActionDefinition]] = [:]
    var byAction: [ActionID: [ActionEffect]] = [:]
    for action in actions {
      byAction[action.id] = action.effects
      for effect in action.effects {
        byGoal[effect.goal, default: []].append(action)
      }
    }
    actionsByGoal = byGoal
    effectsByAction = byAction
  }

  public func actionsAffecting(_ goal: GoalID) -> [ActionDefinition] {
    actionsByGoal[goal] ?? []
  }

  public func effects(of action: ActionID) -> [ActionEffect] {
    effectsByAction[action] ?? []
  }

  /// Actions that positively affect at least two of the supplied goals are
  /// candidate shared root causes.
  public func sharedCauses(for goals: Set<GoalID>) -> [ActionDefinition] {
    guard goals.count > 1 else { return [] }
    var unique: [ActionID: ActionDefinition] = [:]
    for goal in goals {
      for action in actionsAffecting(goal) {
        let covered = action.effects.filter {
          $0.expectedImprovement > 0 && goals.contains($0.goal)
        }.count
        if covered >= 2 { unique[action.id] = action }
      }
    }
    return Array(unique.values)
  }

  public func touchedGoals(by actions: [ActionDefinition]) -> Set<GoalID> {
    actions.reduce(into: Set<GoalID>()) { result, action in
      result.formUnion(action.touchedGoals)
    }
  }
}
