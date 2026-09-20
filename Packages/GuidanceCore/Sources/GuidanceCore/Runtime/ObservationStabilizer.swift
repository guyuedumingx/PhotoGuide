import Foundation

public struct TemporalStabilizationPolicy: Sendable {
  public var windowSize = 4
  public var minimumSamples = 2
  public var recencyDecay = 0.72
  public var normalizedEntropyLimit = 0.72
  public var continuousJitterTolerance = 0.035
  public var maxFrameGap = 12

  public init() {}
}

public struct StabilizedObservation: Sendable {
  public let observation: Observation
  public let isStable: Bool
  public let instability: Double
  public let sampleCount: Int

  public init(observation: Observation, isStable: Bool, instability: Double, sampleCount: Int) {
    self.observation = observation
    self.isStable = isStable
    self.instability = min(max(instability, 0), 1)
    self.sampleCount = sampleCount
  }
}

private struct StabilizerKey: Hashable {
  let dimension: DimensionID
  let binding: Binding
  let evaluator: EvaluatorID
}

/// Short-window temporal stabilizer for semantic or otherwise noisy evaluators.
/// It never changes recipe semantics; it only turns inconsistent evidence into
/// lower confidence so the GoalEngine can choose UNKNOWN/HOLD instead of motion.
public struct ObservationStabilizer: Sendable {
  public var policy: TemporalStabilizationPolicy
  private var history: [StabilizerKey: [Observation]] = [:]

  public init(policy: TemporalStabilizationPolicy = .init()) {
    self.policy = policy
  }

  public mutating func reset() { history.removeAll() }

  public mutating func ingest(_ observation: Observation) -> StabilizedObservation {
    let key = StabilizerKey(
      dimension: observation.dimension,
      binding: observation.binding,
      evaluator: observation.evaluator
    )
    var values = history[key] ?? []

    if let last = values.last {
      let contextChanged =
        last.bindingVersion != observation.bindingVersion
        || last.sceneRevision != observation.sceneRevision
      let largeGap =
        observation.frameID < last.frameID
        || observation.frameID - last.frameID > policy.maxFrameGap
      if contextChanged || largeGap { values.removeAll() }
    }

    if let last = values.last, observation.frameID == last.frameID {
      values[values.count - 1] = observation
    } else {
      values.append(observation)
    }
    if values.count > max(1, policy.windowSize) {
      values.removeFirst(values.count - max(1, policy.windowSize))
    }
    history[key] = values

    return stabilize(values, fallback: observation)
  }

  private func stabilize(
    _ values: [Observation],
    fallback: Observation
  ) -> StabilizedObservation {
    // `ingest` always appends before stabilization, but retain a safe fallback
    // so a future refactor cannot turn an internal invariant into a process trap.
    let newest = values.last ?? fallback
    let sampleCount = values.count
    let enoughSamples = sampleCount >= max(1, policy.minimumSamples)

    switch newest.value {
    case .continuous:
      let pairs = weighted(values).compactMap { observation, weight -> (Double, Double)? in
        guard case .continuous(let value) = observation.value, value.isFinite else { return nil }
        return (value, weight)
      }
      let weightSum = pairs.reduce(0.0) { $0 + $1.1 }
      guard weightSum > 0 else {
        return .init(
          observation: downgraded(newest, multiplier: 0), isStable: false, instability: 1,
          sampleCount: sampleCount)
      }
      let mean = pairs.reduce(0.0) { $0 + $1.0 * $1.1 } / weightSum
      let variance = pairs.reduce(0.0) { $0 + pow($1.0 - mean, 2) * $1.1 } / weightSum
      let std = sqrt(max(0, variance))
      let instability = min(1, std / max(0.000_001, policy.continuousJitterTolerance))
      let stable = enoughSamples && std <= policy.continuousJitterTolerance
      let confidence = weightedConfidence(values) * (1 - min(0.85, instability * 0.75))
      let output = Observation(
        dimension: newest.dimension, binding: newest.binding, value: .continuous(mean),
        confidence: stable ? confidence : min(confidence, 0.45),
        evaluator: newest.evaluator, frameID: newest.frameID, timestamp: newest.timestamp,
        bindingVersion: newest.bindingVersion, sceneRevision: newest.sceneRevision)
      return .init(
        observation: output, isStable: stable, instability: instability, sampleCount: sampleCount)

    case .ordinal:
      var mass = [String: Double]()
      for (observation, weight) in weighted(values) {
        if let distribution = observation.distribution, !distribution.isEmpty {
          let valid = distribution.filter { $0.value.isFinite && $0.value > 0 }
          let total = valid.values.reduce(0, +)
          if total > 0 {
            for (label, probability) in valid {
              mass[label, default: 0] += weight * probability / total
            }
          }
        } else if case .ordinal(let value) = observation.value {
          mass[String(value), default: 0] += weight
        }
      }
      return discreteResult(newest: newest, mass: mass, values: values, sampleCount: sampleCount) {
        label in
        .ordinal(Int(label) ?? 0)
      }

    case .boolean:
      var mass = [String: Double]()
      for (observation, weight) in weighted(values) {
        if case .boolean(let value) = observation.value {
          mass[value ? "true" : "false", default: 0] += weight
        }
      }
      return discreteResult(newest: newest, mass: mass, values: values, sampleCount: sampleCount) {
        .boolean($0 == "true")
      }

    case .categorical:
      var mass = [String: Double]()
      for (observation, weight) in weighted(values) {
        if case .categorical(let value) = observation.value { mass[value, default: 0] += weight }
      }
      return discreteResult(newest: newest, mass: mass, values: values, sampleCount: sampleCount) {
        .categorical($0)
      }
    }
  }

  private func discreteResult(
    newest: Observation,
    mass: [String: Double],
    values: [Observation],
    sampleCount: Int,
    makeValue: (String) -> DimensionValue
  ) -> StabilizedObservation {
    let total = mass.values.reduce(0, +)
    guard total > 0, let winner = mass.max(by: { $0.value < $1.value }) else {
      return .init(
        observation: downgraded(newest, multiplier: 0), isStable: false, instability: 1,
        sampleCount: sampleCount)
    }
    let distribution = mass.mapValues { $0 / total }
    let entropy = normalizedEntropy(distribution)
    let enoughSamples = sampleCount >= max(1, policy.minimumSamples)
    let stable = enoughSamples && entropy <= policy.normalizedEntropyLimit
    let peak = distribution[winner.key] ?? 0
    let confidence = weightedConfidence(values)
    let effectiveConfidence = min(
      1, max(0, max(confidence, newest.confidence) * peak * (1 - entropy * 0.5)))
    let output = Observation(
      dimension: newest.dimension,
      binding: newest.binding,
      value: makeValue(winner.key),
      confidence: stable ? effectiveConfidence : min(effectiveConfidence, 0.45),
      evaluator: newest.evaluator,
      distribution: distribution,
      frameID: newest.frameID,
      timestamp: newest.timestamp,
      bindingVersion: newest.bindingVersion,
      sceneRevision: newest.sceneRevision
    )
    return .init(
      observation: output, isStable: stable, instability: entropy, sampleCount: sampleCount)
  }

  private func weighted(_ values: [Observation]) -> [(Observation, Double)] {
    let count = values.count
    return values.enumerated().map { index, observation in
      let age = count - 1 - index
      let recency = pow(min(max(policy.recencyDecay, 0.01), 1), Double(age))
      return (observation, max(0.000_001, recency * observation.confidence))
    }
  }

  private func weightedConfidence(_ values: [Observation]) -> Double {
    let pairs = weighted(values)
    let recencyMass = pairs.reduce(0.0) { partial, pair in
      let confidence = max(pair.0.confidence, 0.000_001)
      return partial + pair.1 / confidence
    }
    guard recencyMass > 0 else { return 0 }
    return min(1, pairs.reduce(0.0) { $0 + $1.1 } / recencyMass)
  }

  private func normalizedEntropy(_ distribution: [String: Double]) -> Double {
    let probabilities = distribution.values.filter { $0 > 0 }
    guard probabilities.count > 1 else { return 0 }
    let entropy = -probabilities.reduce(0.0) { $0 + $1 * log($1) }
    return min(1, max(0, entropy / log(Double(probabilities.count))))
  }

  private func downgraded(_ observation: Observation, multiplier: Double) -> Observation {
    Observation(
      dimension: observation.dimension,
      binding: observation.binding,
      value: observation.value,
      confidence: observation.confidence * multiplier,
      evaluator: observation.evaluator,
      distribution: observation.distribution,
      frameID: observation.frameID,
      timestamp: observation.timestamp,
      bindingVersion: observation.bindingVersion,
      sceneRevision: observation.sceneRevision
    )
  }
}
