import Foundation

public struct ActionVerifier: Sendable {
  public var improvementThreshold = 0.08
  public var oppositeThreshold = -0.05
  public var minimumComparableEffects = 1
  public var regressionTolerance = 0.04
  public var coreRegressionLimit = 0.14

  public init() {}

  public func verify(_ instance: ActionInstance, engine: GoalEngine) -> ActionVerification {

    if instance.definition.isInformationSeeking {
      return verifyInformation(instance, engine: engine)
    }
    let comparable = instance.definition.effects.compactMap { effect -> (Double, Double)? in
      guard effect.expectedImprovement > 0,
        let before = instance.baselineScores[effect.goal],
        let after = engine.score(for: effect.goal),
        evidenceIsComparable(goal: effect.goal, instance: instance, engine: engine)
      else { return nil }
      return (after - before, max(0.01, effect.expectedImprovement))
    }
    guard comparable.count >= minimumComparableEffects else { return .inconclusive }

    // Verify side effects too. An action that fixes one target while breaking a
    // HARD/locked goal is not a successful action and must not be learned as one.
    var excessiveCoreRegression = false
    for effect in instance.definition.effects {
      guard let before = instance.baselineScores[effect.goal],
        let after = engine.score(for: effect.goal),
        evidenceIsComparable(goal: effect.goal, instance: instance, engine: engine),
        let definition = engine.definitions[effect.goal],
        let runtime = engine.states[effect.goal]
      else { continue }

      let actualDamage = max(0, before - after)
      let allowedDamage = min(1, effect.possibleDamage + regressionTolerance)
      guard actualDamage > allowedDamage else { continue }

      if definition.constraint == .hard || runtime.policy == .locked {
        return .oppositeEffect
      }
      if definition.constraint == .core, actualDamage >= coreRegressionLimit {
        excessiveCoreRegression = true
      }
    }

    let weightSum = comparable.reduce(0.0) { $0 + $1.1 }
    guard weightSum > 0 else { return .inconclusive }
    let weightedDelta = comparable.reduce(0.0) { $0 + $1.0 * $1.1 } / weightSum

    if weightedDelta <= oppositeThreshold { return .oppositeEffect }
    if excessiveCoreRegression {
      return weightedDelta >= improvementThreshold ? .partial : .noEffect
    }
    if weightedDelta >= improvementThreshold { return .improved }
    if weightedDelta > 0 { return .partial }
    return .noEffect
  }

  private func verifyInformation(_ instance: ActionInstance, engine: GoalEngine)
    -> ActionVerification
  {
    var weightedGain = 0.0
    var expectedWeight = 0.0
    var comparable = 0

    for effect in instance.definition.informationEffects
    where instance.verificationGoals.contains(effect.goal) {
      guard let runtime = engine.states[effect.goal],
        let currentFrame = runtime.lastUpdatedFrame
      else { continue }
      if let baseline = instance.baselineEvidence[effect.goal], currentFrame <= baseline.frameID {
        continue
      }

      let before = instance.baselineConfidence[effect.goal] ?? 0
      let after = runtime.confidence ?? 0
      let confidenceDelta = max(-1, min(1, after - before))
      let resolved =
        runtime.state != .unknown && runtime.state != .unresolved && runtime.state != .inactive
      let resolutionBonus = resolved ? 0.35 * effect.resolutionProbability : 0
      let value = confidenceDelta + resolutionBonus
      let weight = max(0.05, effect.confidenceGain + effect.resolutionProbability * 0.5)
      weightedGain += value * weight
      expectedWeight += weight
      comparable += 1
    }

    guard comparable > 0, expectedWeight > 0 else { return .inconclusive }
    let result = weightedGain / expectedWeight
    if result <= oppositeThreshold { return .oppositeEffect }
    if result >= improvementThreshold { return .improved }
    if result > 0 { return .partial }
    return .noEffect
  }

  private func evidenceIsComparable(
    goal: GoalID,
    instance: ActionInstance,
    engine: GoalEngine
  ) -> Bool {
    guard let current = engine.observation(for: goal) else { return false }
    guard let baseline = instance.baselineEvidence[goal] else { return true }
    return baseline.bindingVersion == current.bindingVersion
      && baseline.sceneRevision == current.sceneRevision
      && current.frameID > baseline.frameID
  }
}
