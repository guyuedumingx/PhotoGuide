import Foundation

/// Bounded look-ahead planner for short action sequences. It deliberately uses
/// declared probabilistic effects rather than mutating GoalEngine state. The
/// horizon is kept small because a live camera scene invalidates long plans.
public struct ActionSequencePlanner: Sendable {
  public var maxDepth = 3
  public var beamWidth = 8
  public var minimumPlanAdvantage = 0.12
  public var extraStepInteractionCost = 0.07
  public var uncertaintyModel = PlanningUncertaintyModel()

  public init() {}

  public func bestPlan(
    engine: GoalEngine,
    planner: ActionPlanner,
    actions: [ActionDefinition],
    goalGroups: [GoalGroupDefinition] = [],
    startingWith requiredFirstAction: ActionDefinition? = nil
  ) -> ActionPlanDefinition? {
    let feasible = actions.filter {
      !$0.isInformationSeeking && planner.feasible($0, engine: engine)
    }
    guard feasible.count >= 2 else { return nil }

    let activeCritical = Set(
      engine.states.compactMap { id, runtime -> GoalID? in
        guard runtime.policy != .skipped,
          runtime.state == .active || runtime.state == .drifted,
          engine.definitions[id]?.constraint != .soft
        else { return nil }
        return id
      })
    guard !activeCritical.isEmpty else { return nil }

    let initialScores = Dictionary(
      uniqueKeysWithValues: engine.states.compactMap { id, runtime in
        runtime.score.map { (id, $0) }
      })
    struct Candidate {
      let steps: [ActionDefinition]
      let scores: [GoalID: Double]
      let meanUtility: Double
      let adjustedUtility: Double
      let uncertainty: Double
      let relaxed: Set<GoalID>
    }

    var frontier: [Candidate] = [
      Candidate(
        steps: [], scores: initialScores, meanUtility: 0, adjustedUtility: 0, uncertainty: 0,
        relaxed: [])
    ]
    var best: Candidate?

    for depth in 1...max(2, maxDepth) {
      var next: [Candidate] = []
      for candidate in frontier {
        for action in feasible where !candidate.steps.contains(where: { $0.id == action.id }) {
          if depth == 1, let requiredFirstAction, action.id != requiredFirstAction.id { continue }
          // A sequence is never allowed to intentionally regress HARD or locked
          // goals. Those are controller invariants, not trade-offs.
          let forbiddenDamage = action.effects.contains { effect in
            guard effect.possibleDamage > 0,
              let definition = engine.definitions[effect.goal],
              let runtime = engine.states[effect.goal]
            else { return false }
            return definition.constraint == .hard || runtime.policy == .locked
          }
          if forbiddenDamage { continue }

          var scores = candidate.scores
          var relaxed = candidate.relaxed
          let learnedGain = planner.memory.effectModel.gainMultiplier(for: action)
          for effect in action.effects {
            let old = scores[effect.goal] ?? engine.states[effect.goal]?.score ?? 0
            let effectiveImprovement = min(1, effect.expectedImprovement * learnedGain)
            let improved = old + (1 - old) * effectiveImprovement
            let damaged = improved * (1 - effect.possibleDamage)
            scores[effect.goal] = min(max(damaged, 0), 1)
            if effect.possibleDamage > 0,
              engine.definitions[effect.goal]?.constraint != .hard,
              engine.states[effect.goal]?.policy != .locked
            {
              relaxed.insert(effect.goal)
            }
          }

          // A later step that positively repairs a goal removes it from the
          // temporary relaxation set once its simulated quality recovers.
          for effect in action.effects where effect.expectedImprovement > effect.possibleDamage {
            if (scores[effect.goal] ?? 0) >= (initialScores[effect.goal] ?? 0) {
              relaxed.remove(effect.goal)
            }
          }

          let steps = candidate.steps + [action]
          let predictedBenefit = benefit(
            from: initialScores, to: scores, engine: engine, goalGroups: goalGroups)
          let directCosts = steps.reduce(0.0) {
            $0 + $1.burden + $1.risk + ($1.safety == .contextDependent ? 0.12 : 0)
          }
          let interactionCost = Double(max(0, steps.count - 1)) * extraStepInteractionCost
          let behaviorPenalty = steps.reduce(0.0) { total, step in
            total
              + Double(planner.memory.declinePenalty[step.id] ?? 0) * 0.75
              + Double(planner.memory.failurePenalty[step.id] ?? 0) * 0.90
          }
          let meanUtility = predictedBenefit - directCosts - behaviorPenalty - interactionCost
          let distribution = uncertaintyModel.estimate(
            meanUtility: meanUtility, actions: steps, planner: planner)
          let expanded = Candidate(
            steps: steps,
            scores: scores,
            meanUtility: distribution.mean,
            adjustedUtility: distribution.confidenceAdjusted,
            uncertainty: distribution.uncertainty,
            relaxed: relaxed
          )
          next.append(expanded)

          if depth >= 2 {
            if let currentBest = best {
              if distribution.confidenceAdjusted > currentBest.adjustedUtility { best = expanded }
            } else {
              best = expanded
            }
          }
        }
      }
      frontier = Array(
        next.sorted { $0.adjustedUtility > $1.adjustedUtility }.prefix(max(1, beamWidth)))
      if frontier.isEmpty { break }
    }

    guard let best, best.steps.count >= 2 else { return nil }
    let bestSingle =
      feasible.map {
        planner.utility($0, engine: engine, goalGroups: goalGroups)
      }.max() ?? -.infinity
    guard best.adjustedUtility >= bestSingle + minimumPlanAdvantage else { return nil }

    let signature = best.steps.map(\.id.rawValue).joined(separator: ">")
    return ActionPlanDefinition(
      id: ActionPlanID("plan.\(signature)"),
      steps: best.steps,
      expectedUtility: best.meanUtility,
      utilityUncertainty: best.uncertainty,
      confidenceAdjustedUtility: best.adjustedUtility,
      temporarilyRelaxedGoals: best.relaxed
    )
  }

  private func benefit(
    from initial: [GoalID: Double],
    to final: [GoalID: Double],
    engine: GoalEngine,
    goalGroups: [GoalGroupDefinition]
  ) -> Double {
    final.reduce(into: 0.0) { total, pair in
      let (id, score) = pair
      guard engine.states[id]?.policy != .skipped else { return }
      let before = initial[id] ?? 0
      let delta = score - before
      let priority = GoalSetPlanner().priority(of: id, engine: engine, goalGroups: goalGroups)
      total += delta * priority
    }
  }
}
