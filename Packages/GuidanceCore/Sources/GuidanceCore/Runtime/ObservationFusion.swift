import Foundation

public struct ObservationFusionResult: Equatable, Sendable {
  public let observation: Observation
  public let conflict: ObservationConflictReport

  public init(observation: Observation, conflict: ObservationConflictReport) {
    self.observation = observation
    self.conflict = conflict
  }
}

public struct ObservationFusion: Sendable {
  public var evaluatorTrust: [EvaluatorID: Double]
  public var frameRecencyDecay: Double
  public var severeConflictConfidenceCeiling: Double
  public var mildConflictConfidenceMultiplier: Double

  public init(
    evaluatorTrust: [EvaluatorID: Double] = [:],
    frameRecencyDecay: Double = 0.82,
    severeConflictConfidenceCeiling: Double = 0.32,
    mildConflictConfidenceMultiplier: Double = 0.72
  ) {
    self.evaluatorTrust = evaluatorTrust
    self.frameRecencyDecay = min(max(frameRecencyDecay, 0.1), 1)
    self.severeConflictConfidenceCeiling = min(max(severeConflictConfidenceCeiling, 0), 1)
    self.mildConflictConfidenceMultiplier = min(max(mildConflictConfidenceMultiplier, 0), 1)
  }

  public func fuse(_ observations: [Observation], allowFrameSkew: Int = 0) -> Observation? {
    fuseDetailed(observations, allowFrameSkew: allowFrameSkew)?.observation
  }

  public func fuseDetailed(
    _ observations: [Observation],
    allowFrameSkew: Int = 0,
    reliabilityModel: EvaluatorReliabilityModel? = nil,
    sceneConditions: SceneConditionProfile? = nil,
    registry: GuidanceRegistry? = nil
  ) -> ObservationFusionResult? {
    guard let first = observations.first else { return nil }
    let newestFrame = observations.map(\.frameID).max() ?? first.frameID
    guard
      observations.allSatisfy({
        $0.dimension == first.dimension
          && $0.binding == first.binding
          && newestFrame - $0.frameID >= 0
          && newestFrame - $0.frameID <= max(0, allowFrameSkew)
          && $0.bindingVersion == first.bindingVersion
          && $0.sceneRevision == first.sceneRevision
      })
    else { return nil }

    let model = reliabilityModel ?? EvaluatorReliabilityModel(baseReliability: evaluatorTrust)
    let conflict = ObservationConflictArbitrator().report(
      observations,
      reliability: model,
      sceneConditions: sceneConditions,
      registry: registry
    )

    let sourceFactors = observations.map { observation -> (trust: Double, freshness: Double) in
      let learned = reliabilityModel?.resolvedReliability(
        for: observation.evaluator,
        dimension: observation.dimension,
        sceneConditions: sceneConditions,
        registry: registry
      )
      let fallbackBase = evaluatorTrust[observation.evaluator] ?? 1
      let fallbackMultiplier = SceneConditionReliabilityAdjuster().multiplier(
        evaluator: registry?.evaluators[observation.evaluator],
        dimension: observation.dimension,
        profile: sceneConditions
      )
      let trust = min(max(learned ?? fallbackBase * fallbackMultiplier, 0), 1)
      let frameAge = newestFrame - observation.frameID
      let freshness = pow(frameRecencyDecay, Double(max(0, frameAge)))
      return (trust, freshness)
    }

    // Reliability must influence absolute evidence confidence, not only which
    // source wins a disagreement. Otherwise one known-unreliable evaluator
    // would still be accepted at full confidence when it is the sole source.
    if observations.count == 1, let factors = sourceFactors.first {
      let adjustedConfidence = first.confidence * sqrt(max(0, factors.trust * factors.freshness))
      let adjusted = Observation(
        dimension: first.dimension,
        binding: first.binding,
        value: first.value,
        confidence: adjustedConfidence,
        evaluator: first.evaluator,
        distribution: first.distribution,
        frameID: first.frameID,
        timestamp: first.timestamp,
        bindingVersion: first.bindingVersion,
        sceneRevision: first.sceneRevision
      )
      return .init(observation: adjusted, conflict: conflict)
    }

    let sourceWeights = sourceFactors.map { max(0.000_001, $0.trust * $0.freshness) }
    let weights = zip(observations, sourceWeights).map {
      max(0.000_001, $0.0.confidence * $0.1)
    }
    let effectiveConfidences = zip(observations, sourceFactors).map { pair in
      pair.0.confidence * sqrt(max(0, pair.1.trust * pair.1.freshness))
    }
    let baseConfidence =
      effectiveConfidences.reduce(0, +) / Double(max(1, effectiveConfidences.count))

    let fused: (DimensionValue, Double, [String: Double]?)?
    switch first.value {
    case .continuous:
      guard observations.allSatisfy({ if case .continuous = $0.value { true } else { false } })
      else {
        guard let strongest = strongest(observations, weights: weights) else { return nil }
        return .init(observation: strongest, conflict: conflict)
      }
      let total = weights.reduce(0, +)
      let mean =
        zip(observations, weights).reduce(0.0) { partial, pair in
          guard case .continuous(let value) = pair.0.value else { return partial }
          return partial + value * pair.1
        } / total
      let variance =
        zip(observations, weights).reduce(0.0) { partial, pair in
          guard case .continuous(let value) = pair.0.value else { return partial }
          return partial + pair.1 * pow(value - mean, 2)
        } / total
      let dispersionPenalty = min(0.9, sqrt(max(0, variance)) * 1.8)
      fused = (.continuous(mean), baseConfidence * (1 - dispersionPenalty), nil)

    case .boolean:
      guard observations.allSatisfy({ if case .boolean = $0.value { true } else { false } }) else {
        guard let strongest = strongest(observations, weights: weights) else { return nil }
        return .init(observation: strongest, conflict: conflict)
      }
      var votes = [true: 0.0, false: 0.0]
      for (observation, weight) in zip(observations, weights) {
        if case .boolean(let value) = observation.value { votes[value, default: 0] += weight }
      }
      let total = max(0.000_001, votes.values.reduce(0, +))
      let selected = (votes[true, default: 0] >= votes[false, default: 0])
      let agreement = max(votes[true, default: 0], votes[false, default: 0]) / total
      fused = (.boolean(selected), baseConfidence * agreement, nil)

    case .categorical:
      guard observations.allSatisfy({ if case .categorical = $0.value { true } else { false } })
      else {
        guard let strongest = strongest(observations, weights: weights) else { return nil }
        return .init(observation: strongest, conflict: conflict)
      }
      var votes = [String: Double]()
      for (observation, weight) in zip(observations, weights) {
        if case .categorical(let value) = observation.value { votes[value, default: 0] += weight }
      }
      guard let winner = votes.max(by: { $0.value < $1.value }) else { return nil }
      let total = max(0.000_001, votes.values.reduce(0, +))
      fused = (.categorical(winner.key), baseConfidence * winner.value / total, normalized(votes))

    case .ordinal:
      guard observations.allSatisfy({ if case .ordinal = $0.value { true } else { false } }) else {
        guard let strongest = strongest(observations, weights: weights) else { return nil }
        return .init(observation: strongest, conflict: conflict)
      }
      var mass = [String: Double]()
      for (observation, weight) in zip(observations, weights) {
        if let distribution = observation.distribution, !distribution.isEmpty {
          let sum = distribution.values.reduce(0, +)
          if sum > 0 {
            for (key, value) in distribution where value > 0 {
              mass[key, default: 0] += weight * (value / sum)
            }
          }
        } else if case .ordinal(let value) = observation.value {
          mass[String(value), default: 0] += weight
        }
      }
      guard let winner = mass.max(by: { $0.value < $1.value }), let value = Int(winner.key) else {
        return nil
      }
      let distribution = normalized(mass)
      let peak = distribution[winner.key] ?? 0
      fused = (.ordinal(value), baseConfidence * peak, distribution)
    }

    guard var fused else { return nil }
    switch conflict.level {
    case .none:
      break
    case .mild:
      fused.1 *= mildConflictConfidenceMultiplier
    case .severe:
      fused.1 = min(fused.1 * max(0.15, conflict.agreement), severeConflictConfidenceCeiling)
    }

    let output = Observation(
      dimension: first.dimension,
      binding: first.binding,
      value: fused.0,
      confidence: min(max(fused.1, 0), 1),
      evaluator: EvaluatorID("core.fusion"),
      distribution: fused.2,
      frameID: newestFrame,
      timestamp: observations.map(\.timestamp).max() ?? first.timestamp,
      bindingVersion: first.bindingVersion,
      sceneRevision: first.sceneRevision
    )
    return .init(observation: output, conflict: conflict)
  }

  private func strongest(_ observations: [Observation], weights: [Double]) -> Observation? {
    zip(observations, weights).max(by: { $0.1 < $1.1 })?.0
  }

  private func normalized(_ values: [String: Double]) -> [String: Double] {
    let total = values.values.reduce(0, +)
    guard total > 0 else { return [:] }
    return values.mapValues { $0 / total }
  }
}
