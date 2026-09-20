import Foundation

public struct EvaluatorReliabilityKey: Hashable, Codable, Sendable {
  public let evaluator: EvaluatorID
  public let dimension: DimensionID

  public init(evaluator: EvaluatorID, dimension: DimensionID) {
    self.evaluator = evaluator
    self.dimension = dimension
  }
}

public struct EvaluatorPairKey: Hashable, Codable, Sendable {
  public let dimension: DimensionID
  public let binding: Binding
  public let bindingVersion: Int
  public let sceneRevision: Int
  public let first: EvaluatorID
  public let second: EvaluatorID
}

public struct EvaluatorPairStamp: Codable, Equatable, Sendable {
  public let firstFrameID: Int
  public let secondFrameID: Int
}

public struct EvaluatorReliabilityState: Codable, Equatable, Sendable {
  public var reliability: Double
  public var sampleCount: Int
  public var agreementEMA: Double
  public var conflictCount: Int
  public var lastFrameID: Int?

  public init(
    reliability: Double,
    sampleCount: Int = 0,
    agreementEMA: Double = 1,
    conflictCount: Int = 0,
    lastFrameID: Int? = nil
  ) {
    self.reliability = Self.clamp(reliability)
    self.sampleCount = max(0, sampleCount)
    self.agreementEMA = Self.clamp(agreementEMA)
    self.conflictCount = max(0, conflictCount)
    self.lastFrameID = lastFrameID
  }

  private static func clamp(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
  }
}

/// Session-local calibration of evaluator trust. It deliberately learns slowly
/// and only from cross-evaluator agreement in the same scene/binding context.
/// This is not ground-truth calibration; it is a runtime arbitration signal.
public struct EvaluatorReliabilityModel: Codable, Equatable, Sendable {
  public var baseReliability: [EvaluatorID: Double]
  public private(set) var states: [EvaluatorReliabilityKey: EvaluatorReliabilityState]
  /// Pair stamps prevent the same pair of evidence frames from training the
  /// reliability model more than once.
  public private(set) var processedPairs: [EvaluatorPairKey: EvaluatorPairStamp]

  /// Slow adaptation prevents a brief disagreement from permanently muting a source.
  public var learningRate: Double
  public var minimumReliability: Double
  public var maximumReliability: Double
  public var minimumPeerMass: Double
  public var severeConflictAgreement: Double
  /// Reliability calibration only compares near-synchronous evidence. Fusion
  /// may accept wider frame skew, but stale evidence must not train trust.
  public var maximumCalibrationFrameDelta: Int
  public var calibrationRecencyDecay: Double

  public init(
    baseReliability: [EvaluatorID: Double] = [:],
    learningRate: Double = 0.08,
    minimumReliability: Double = 0.15,
    maximumReliability: Double = 0.99,
    minimumPeerMass: Double = 0.35,
    severeConflictAgreement: Double = 0.35,
    maximumCalibrationFrameDelta: Int = 2,
    calibrationRecencyDecay: Double = 0.72
  ) {
    self.baseReliability = baseReliability.mapValues(Self.clamp)
    self.states = [:]
    self.processedPairs = [:]
    self.learningRate = min(max(learningRate, 0.001), 0.5)
    self.minimumReliability = min(max(minimumReliability, 0), 1)
    self.maximumReliability = min(max(maximumReliability, self.minimumReliability), 1)
    self.minimumPeerMass = min(max(minimumPeerMass, 0), 1)
    self.severeConflictAgreement = min(max(severeConflictAgreement, 0), 1)
    self.maximumCalibrationFrameDelta = max(0, maximumCalibrationFrameDelta)
    self.calibrationRecencyDecay = min(max(calibrationRecencyDecay, 0.1), 1)
  }

  public func reliability(for evaluator: EvaluatorID, dimension: DimensionID) -> Double {
    let key = EvaluatorReliabilityKey(evaluator: evaluator, dimension: dimension)
    if let state = states[key] { return state.reliability }
    return min(max(baseReliability[evaluator] ?? 0.85, minimumReliability), maximumReliability)
  }

  /// Reliability used for one concrete sensing context. Learned trust remains
  /// unchanged; adverse scene conditions only apply a temporary multiplier.
  public func resolvedReliability(
    for evaluator: EvaluatorID,
    dimension: DimensionID,
    sceneConditions: SceneConditionProfile? = nil,
    registry: GuidanceRegistry? = nil
  ) -> Double {
    let learned = reliability(for: evaluator, dimension: dimension)
    guard let definition = registry?.evaluators[evaluator] else { return learned }
    let multiplier = SceneConditionReliabilityAdjuster().multiplier(
      evaluator: definition, dimension: dimension, profile: sceneConditions)
    return min(max(learned * multiplier, minimumReliability * 0.25), maximumReliability)
  }

  public func trustMap(for dimension: DimensionID, evaluators: some Sequence<EvaluatorID>)
    -> [EvaluatorID: Double]
  {
    Dictionary(
      uniqueKeysWithValues: evaluators.map { ($0, reliability(for: $0, dimension: dimension)) })
  }

  /// Updates reliability from one same-context evidence set. At least two
  /// independent peers are required before a source is changed; a single
  /// evaluator can never self-confirm its own trust.
  public mutating func observe(
    _ observations: [Observation],
    sceneConditions: SceneConditionProfile? = nil,
    registry: GuidanceRegistry? = nil
  ) {
    let raw = observations.filter { $0.evaluator.rawValue != "core.fusion" }
    guard raw.count >= 2 else { return }

    let groups = Dictionary(grouping: raw) {
      ReliabilityContextKey(
        dimension: $0.dimension,
        binding: $0.binding,
        bindingVersion: $0.bindingVersion,
        sceneRevision: $0.sceneRevision
      )
    }

    for (_, group) in groups where group.count >= 2 {
      updateGroup(group, sceneConditions: sceneConditions, registry: registry)
    }
  }

  /// Removes calibration entries that are no longer legal under the current
  /// registry and refreshes base priors from the current evaluator definitions.
  /// This is used when migrating a schema-v1 checkpoint whose registry was not
  /// part of the saved structural signature.
  public func sanitized(for registry: GuidanceRegistry?) -> EvaluatorReliabilityModel {
    guard let registry else { return self }
    var copy = self
    copy.baseReliability = Dictionary(
      uniqueKeysWithValues: registry.evaluators.values.map { ($0.id, $0.defaultReliability) })
    copy.states = states.filter { key, _ in
      guard registry.evaluators[key.evaluator] != nil,
        registry.dimensions[key.dimension] != nil
      else { return false }
      return true
    }
    copy.processedPairs = processedPairs.filter { key, _ in
      registry.dimensions[key.dimension] != nil
        && registry.evaluators[key.first] != nil
        && registry.evaluators[key.second] != nil
    }
    return copy
  }

  public mutating func reset() {
    states.removeAll()
    processedPairs.removeAll()
  }

  private mutating func updateGroup(
    _ group: [Observation],
    sceneConditions: SceneConditionProfile?,
    registry: GuidanceRegistry?
  ) {
    guard let firstObservation = group.first else { return }
    let sorted = group.sorted { $0.evaluator.rawValue < $1.evaluator.rawValue }

    for leftIndex in sorted.indices {
      for rightIndex in sorted.indices where rightIndex > leftIndex {
        let left = sorted[leftIndex]
        let right = sorted[rightIndex]
        guard left.evaluator != right.evaluator else { continue }
        let frameDelta = abs(left.frameID - right.frameID)
        guard frameDelta <= maximumCalibrationFrameDelta else { continue }

        let firstEvaluator: EvaluatorID
        let secondEvaluator: EvaluatorID
        let firstFrame: Int
        let secondFrame: Int
        if left.evaluator.rawValue <= right.evaluator.rawValue {
          firstEvaluator = left.evaluator
          secondEvaluator = right.evaluator
          firstFrame = left.frameID
          secondFrame = right.frameID
        } else {
          firstEvaluator = right.evaluator
          secondEvaluator = left.evaluator
          firstFrame = right.frameID
          secondFrame = left.frameID
        }
        let pairKey = EvaluatorPairKey(
          dimension: firstObservation.dimension,
          binding: firstObservation.binding,
          bindingVersion: firstObservation.bindingVersion,
          sceneRevision: firstObservation.sceneRevision,
          first: firstEvaluator,
          second: secondEvaluator
        )
        let stamp = EvaluatorPairStamp(firstFrameID: firstFrame, secondFrameID: secondFrame)
        if processedPairs[pairKey] == stamp { continue }
        processedPairs[pairKey] = stamp

        let freshness = pow(calibrationRecencyDecay, Double(frameDelta))
        let leftContext = contextMultiplier(
          evaluator: left.evaluator, dimension: left.dimension,
          sceneConditions: sceneConditions, registry: registry)
        let rightContext = contextMultiplier(
          evaluator: right.evaluator, dimension: right.dimension,
          sceneConditions: sceneConditions, registry: registry)
        // When the sensing context is known to be poor, disagreement should
        // not permanently damage either evaluator's learned trust as quickly.
        let evidenceStrength =
          min(left.confidence, right.confidence)
          * freshness * sqrt(leftContext * rightContext)
        guard evidenceStrength >= minimumPeerMass else { continue }
        let pairAgreement = Self.agreement(left.value, right.value)
        updateEvaluator(left, agreement: pairAgreement, evidenceStrength: evidenceStrength)
        updateEvaluator(right, agreement: pairAgreement, evidenceStrength: evidenceStrength)
      }
    }
  }

  private mutating func updateEvaluator(
    _ observation: Observation,
    agreement: Double,
    evidenceStrength: Double
  ) {
    let key = EvaluatorReliabilityKey(
      evaluator: observation.evaluator, dimension: observation.dimension)
    var state =
      states[key]
      ?? EvaluatorReliabilityState(
        reliability: reliability(for: observation.evaluator, dimension: observation.dimension)
      )
    let alpha = learningRate * min(max(evidenceStrength, 0), 1)
    let updated = state.reliability * (1 - alpha) + agreement * alpha
    state.reliability = min(max(updated, minimumReliability), maximumReliability)
    state.agreementEMA = state.agreementEMA * (1 - alpha) + agreement * alpha
    state.sampleCount += 1
    if agreement <= severeConflictAgreement { state.conflictCount += 1 }
    state.lastFrameID = observation.frameID
    states[key] = state
  }

  private func contextMultiplier(
    evaluator: EvaluatorID,
    dimension: DimensionID,
    sceneConditions: SceneConditionProfile?,
    registry: GuidanceRegistry?
  ) -> Double {
    guard let definition = registry?.evaluators[evaluator] else { return 1 }
    return SceneConditionReliabilityAdjuster().multiplier(
      evaluator: definition, dimension: dimension, profile: sceneConditions)
  }

  public static func agreement(_ lhs: DimensionValue, _ rhs: DimensionValue) -> Double {
    switch (lhs, rhs) {
    case (.boolean(let a), .boolean(let b)):
      return a == b ? 1 : 0
    case (.categorical(let a), .categorical(let b)):
      return a == b ? 1 : 0
    case (.ordinal(let a), .ordinal(let b)):
      // Standard PhotoGuide ordinal dimensions currently use a compact -2...2
      // scale. A one-step disagreement remains partially compatible; two or
      // more steps is treated as strong conflict.
      return max(0, 1 - Double(abs(a - b)) / 4.0)
    case (.continuous(let a), .continuous(let b)):
      guard a.isFinite, b.isFinite else { return 0 }
      return max(0, 1 - min(abs(a - b), 1))
    default:
      return 0
    }
  }

  private static func clamp(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
  }
}

private struct ReliabilityContextKey: Hashable {
  let dimension: DimensionID
  let binding: Binding
  let bindingVersion: Int
  let sceneRevision: Int
}

public enum ObservationConflictLevel: String, Codable, Sendable {
  case none
  case mild
  case severe
}

public struct ObservationConflictReport: Codable, Equatable, Sendable {
  public let level: ObservationConflictLevel
  public let agreement: Double
  public let strongestEvaluator: EvaluatorID?
  public let strongestShare: Double

  public init(
    level: ObservationConflictLevel,
    agreement: Double,
    strongestEvaluator: EvaluatorID?,
    strongestShare: Double
  ) {
    self.level = level
    self.agreement = min(max(agreement, 0), 1)
    self.strongestEvaluator = strongestEvaluator
    self.strongestShare = min(max(strongestShare, 0), 1)
  }
}

/// Detects when multiple high-confidence evaluators materially disagree. The
/// arbitrator never invents a winner; it only reports whether fusion confidence
/// should be reduced or collapsed to UNKNOWN.
public struct ObservationConflictArbitrator: Sendable {
  public var severeAgreementThreshold = 0.35
  public var mildAgreementThreshold = 0.70
  public var dominanceThreshold = 0.72

  public init() {}

  public func report(
    _ observations: [Observation],
    reliability: EvaluatorReliabilityModel,
    sceneConditions: SceneConditionProfile? = nil,
    registry: GuidanceRegistry? = nil
  ) -> ObservationConflictReport {
    guard let first = observations.first else {
      return .init(level: .none, agreement: 1, strongestEvaluator: nil, strongestShare: 1)
    }
    guard observations.count >= 2 else {
      return .init(
        level: .none, agreement: 1, strongestEvaluator: first.evaluator, strongestShare: 1)
    }

    var weightedAgreement = 0.0
    var pairMass = 0.0
    for i in observations.indices {
      for j in observations.indices where j > i {
        let left = observations[i]
        let right = observations[j]
        let lw =
          reliability.resolvedReliability(
            for: left.evaluator, dimension: first.dimension,
            sceneConditions: sceneConditions, registry: registry) * left.confidence
        let rw =
          reliability.resolvedReliability(
            for: right.evaluator, dimension: first.dimension,
            sceneConditions: sceneConditions, registry: registry) * right.confidence
        let mass = sqrt(max(0, lw * rw))
        guard mass > 0 else { continue }
        weightedAgreement += EvaluatorReliabilityModel.agreement(left.value, right.value) * mass
        pairMass += mass
      }
    }

    let agreement = pairMass > 0 ? weightedAgreement / pairMass : 1
    let weights = observations.map {
      reliability.resolvedReliability(
        for: $0.evaluator, dimension: first.dimension,
        sceneConditions: sceneConditions, registry: registry) * $0.confidence
    }
    let total = max(0.000_001, weights.reduce(0, +))
    let strongestIndex = weights.indices.max(by: { weights[$0] < weights[$1] })
    let strongestShare = strongestIndex.map { weights[$0] / total } ?? 0
    let strongestEvaluator = strongestIndex.map { observations[$0].evaluator }

    let level: ObservationConflictLevel
    if agreement < severeAgreementThreshold && strongestShare < dominanceThreshold {
      level = .severe
    } else if agreement < mildAgreementThreshold {
      level = .mild
    } else {
      level = .none
    }

    return .init(
      level: level,
      agreement: agreement,
      strongestEvaluator: strongestEvaluator,
      strongestShare: strongestShare
    )
  }
}
