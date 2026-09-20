import Foundation

public struct RecipeSimulationResult: Equatable, Sendable {
  public let converged: Bool
  public let steps: Int
  public let finalScores: [GoalID: Double]
  public let unresolvedCriticalGoals: Set<GoalID>

  public init(
    converged: Bool,
    steps: Int,
    finalScores: [GoalID: Double],
    unresolvedCriticalGoals: Set<GoalID>
  ) {
    self.converged = converged
    self.steps = steps
    self.finalScores = finalScores
    self.unresolvedCriticalGoals = unresolvedCriticalGoals
  }
}

/// A deliberately conservative static controller simulation used by the
/// recipe linter. It is not a promise that a physical scene is reachable; it
/// asks a narrower question: given the recipe's own effect declarations, is
/// there at least a coherent sequence of non-restricted actions that can move
/// an abstract bad state toward a usable state without getting stuck?
public struct RecipeSimulationAnalyzer: Sendable {
  public var maximumSteps = 48
  public var hardTarget = 0.82
  public var coreTarget = 0.62
  public var minimumProgress = 0.0005

  public init() {}

  public func simulate(
    goals: [GoalDefinition],
    actions: [ActionDefinition],
    goalGroups: [GoalGroupDefinition] = []
  ) -> RecipeSimulationResult {
    let definitions = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })
    let critical = Set(goals.filter { $0.constraint != .soft }.map(\.id))
    var scores = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, 0.0) })
    var step = 0

    func target(for id: GoalID) -> Double {
      definitions[id]?.constraint == .hard ? hardTarget : coreTarget
    }

    func dependenciesSatisfied(_ id: GoalID) -> Bool {
      guard let goal = definitions[id] else { return false }
      return goal.dependencies.allSatisfy { scores[$0, default: 0] >= target(for: $0) }
    }

    func unresolved() -> Set<GoalID> {
      Set(critical.filter { scores[$0, default: 0] + 0.0001 < target(for: $0) })
    }

    while step < max(1, maximumSteps) {
      let remaining = unresolved()
      if remaining.isEmpty {
        return .init(converged: true, steps: step, finalScores: scores, unresolvedCriticalGoals: [])
      }

      let active = Set(remaining.filter(dependenciesSatisfied))
      let candidates = actions.filter { action in
        action.safety != .restricted && !action.improvedGoals.isDisjoint(with: active)
      }

      var best: ActionDefinition?
      var bestGain = 0.0
      for action in candidates {
        var gain = 0.0
        for effect in action.effects {
          guard let definition = definitions[effect.goal] else { continue }
          let current = scores[effect.goal, default: 0]
          let importance = max(0.05, definition.importance)
          let classWeight: Double =
            switch definition.constraint {
            case .hard: 3.0
            case .core: 1.8
            case .soft: 0.35
            }
          gain += classWeight * importance * effect.expectedImprovement * (1 - current)
          gain -= classWeight * importance * effect.possibleDamage * current
        }
        gain -= action.burden * 0.3 + action.risk * 0.5 + action.uncertainty * 0.2
        if gain > bestGain {
          bestGain = gain
          best = action
        }
      }

      guard let best, bestGain >= minimumProgress else { break }
      let before = scores
      for effect in best.effects {
        let current = scores[effect.goal, default: 0]
        let improved = current + effect.expectedImprovement * (1 - current)
        let damaged = improved - effect.possibleDamage * improved
        scores[effect.goal] = min(max(damaged, 0), 1)
      }
      step += 1

      let delta = scores.reduce(0.0) { partial, item in
        partial + abs(item.value - before[item.key, default: 0])
      }
      if delta < minimumProgress { break }
    }

    let remaining = unresolved()
    return .init(
      converged: remaining.isEmpty,
      steps: step,
      finalScores: scores,
      unresolvedCriticalGoals: remaining
    )
  }
}
