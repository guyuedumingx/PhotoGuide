import Foundation

/// Deterministic goal-state engine. Mutable reference type by design; callers
/// should serialize access (GuidanceViewModel currently owns it on MainActor).
public final class GoalEngine {
  public let definitions: [GoalID: GoalDefinition]
  public private(set) var states: [GoalID: GoalRuntimeState]
  public private(set) var latestObservations: [GoalID: Observation] = [:]
  public let graph: DependencyGraph
  public let evaluationOrder: [GoalID]

  public var minimumConfidence = 0.5
  public var enterFramesOverride = 0
  public var exitFramesOverride = 0
  public var evaluatorTrust: [EvaluatorID: Double] = [:]
  /// Optional registry and scene context used to temporarily adjust evaluator
  /// reliability without corrupting session-learned trust.
  public var reliabilityRegistry: GuidanceRegistry?
  public var sceneConditions: SceneConditionProfile?
  /// Session-local learned trust layered on top of registry defaults.
  public var evaluatorReliability = EvaluatorReliabilityModel()
  public private(set) var latestConflictReports: [GoalID: ObservationConflictReport] = [:]
  /// Different evaluators may complete asynchronously. Evidence from the same
  /// scene can still be fused when it is only a few camera frames apart.
  public var maximumFusionFrameDelta = 6

  private var recentEvidence: [GoalID: [EvaluatorID: Observation]] = [:]

  public init(_ definitions: [GoalDefinition]) {
    var definitionMap = [GoalID: GoalDefinition]()
    for definition in definitions { definitionMap[definition.id] = definition }
    self.definitions = definitionMap
    states = Dictionary(
      uniqueKeysWithValues: definitionMap.map { id, definition in
        var state = GoalRuntimeState()
        if !definition.dependencies.isEmpty { state.state = .inactive }
        return (id, state)
      })
    graph = DependencyGraph(Array(definitionMap.values))
    evaluationOrder =
      graph.topologicalOrder()
      ?? definitionMap.keys.sorted { $0.rawValue < $1.rawValue }
  }

  /// Drops all scene-bound evidence while preserving recipe definitions and
  /// session-learned evaluator reliability. Used after camera interruption,
  /// foreground recovery, or checkpoint restore so stale observations can
  /// never produce an immediate READY state.
  public func resetRuntimeEvidence(preservingPolicies policies: [GoalID: UserGoalPolicy] = [:]) {
    states = Dictionary(
      uniqueKeysWithValues: definitions.map { id, definition in
        var state = GoalRuntimeState()
        if !definition.dependencies.isEmpty { state.state = .inactive }
        if let policy = policies[id] { state.policy = policy }
        return (id, state)
      }
    )
    latestObservations.removeAll()
    recentEvidence.removeAll()
    latestConflictReports.removeAll()
    sceneConditions = nil
  }

  @discardableResult
  public func ingest(_ observation: Observation) -> [GoalID] {
    var updated = [GoalID]()
    for id in evaluationOrder {
      guard let definition = definitions[id],
        definition.dimension == observation.dimension,
        definition.binding == observation.binding
      else { continue }
      guard accept(observation, for: id) else { continue }
      let fused = accumulateAndFuse(observation, for: id)
      latestObservations[id] = fused
      update(definition, with: fused)
      updated.append(id)
    }
    return updated
  }

  /// Batch ingestion gives runtimes an explicit way to submit evaluator results
  /// that belong to one or more camera frames. Evidence is staged before goals
  /// are evaluated in dependency order. This matters when a parent and child
  /// use different dimensions: the child must see the parent's state from the
  /// same frame regardless of the order in which asynchronous evaluators
  /// completed.
  @discardableResult
  public func ingestBatch(_ observations: [Observation]) -> [GoalID] {
    let groups = Dictionary(grouping: observations) { observation in
      ObservationBatchKey(
        bindingVersion: observation.bindingVersion,
        sceneRevision: observation.sceneRevision,
        frameID: observation.frameID
      )
    }
    let orderedKeys = groups.keys.sorted { lhs, rhs in
      if lhs.bindingVersion != rhs.bindingVersion { return lhs.bindingVersion < rhs.bindingVersion }
      if lhs.sceneRevision != rhs.sceneRevision { return lhs.sceneRevision < rhs.sceneRevision }
      return lhs.frameID < rhs.frameID
    }

    var result = Set<GoalID>()
    for key in orderedKeys {
      let group = (groups[key] ?? []).sorted { lhs, rhs in
        if lhs.dimension != rhs.dimension { return lhs.dimension.rawValue < rhs.dimension.rawValue }
        return lhs.evaluator.rawValue < rhs.evaluator.rawValue
      }
      var staged = Set<GoalID>()

      // Stage every matching observation first so child goals can consume
      // evidence produced in the same frame after their parents transition.
      for observation in group {
        for id in evaluationOrder {
          guard let definition = definitions[id],
            definition.dimension == observation.dimension,
            definition.binding == observation.binding,
            accept(observation, for: id)
          else { continue }
          latestObservations[id] = accumulateAndFuse(observation, for: id)
          staged.insert(id)
        }
      }

      for id in evaluationOrder where staged.contains(id) {
        guard let definition = definitions[id], let observation = latestObservations[id] else {
          continue
        }
        update(definition, with: observation)
        result.insert(id)
      }
    }
    return evaluationOrder.filter(result.contains)
  }

  public func score(for id: GoalID) -> Double? { states[id]?.score }
  public func observation(for id: GoalID) -> Observation? { latestObservations[id] }
  public func markDirty(_ id: GoalID) { states[id]?.dirty = true }
  public func clearDirty(_ id: GoalID) { states[id]?.dirty = false }

  public func propagateDirty(from id: GoalID) {
    for dependent in graph.dependents(of: id) { states[dependent]?.dirty = true }
  }

  public func setPolicy(_ policy: UserGoalPolicy, for id: GoalID) {
    guard var runtime = states[id] else { return }
    let oldPolicy = runtime.policy
    guard oldPolicy != policy else { return }
    runtime.policy = policy
    states[id] = runtime

    if policy == .skipped {
      // A skipped parent is treated as satisfied for dependency activation, but
      // its observation is never rewritten as a synthetic success.
      propagateDependencyState(from: id, satisfied: true)
    } else if oldPolicy == .skipped {
      // Re-enabling a skipped parent must restore dependency gating. Otherwise
      // descendants could remain active even though the parent is unresolved.
      propagateDependencyState(from: id, satisfied: runtime.state == .satisfied)
    }
  }

  public func setState(_ state: GoalState, for id: GoalID) { states[id]?.state = state }

  public func isConditionMet(_ condition: ActionCondition) -> Bool {
    switch condition {
    case .always:
      return true
    case .goalUnsatisfied(let id):
      guard let state = states[id]?.state else { return false }
      return state == .active || state == .drifted
    case .continuousBelow(let id, let threshold):
      guard case .continuous(let value)? = latestObservations[id]?.value else { return false }
      return value < threshold
    case .continuousAbove(let id, let threshold):
      guard case .continuous(let value)? = latestObservations[id]?.value else { return false }
      return value > threshold
    case .ordinalBelow(let id, let threshold):
      guard case .ordinal(let value)? = latestObservations[id]?.value else { return false }
      return value < threshold
    case .ordinalAbove(let id, let threshold):
      guard case .ordinal(let value)? = latestObservations[id]?.value else { return false }
      return value > threshold
    case .booleanEquals(let id, let target):
      guard case .boolean(let value)? = latestObservations[id]?.value else { return false }
      return value == target
    }
  }

  private func accept(_ observation: Observation, for id: GoalID) -> Bool {
    if let sameEvaluator = recentEvidence[id]?[observation.evaluator] {
      if observation.bindingVersion < sameEvaluator.bindingVersion { return false }
      if observation.bindingVersion == sameEvaluator.bindingVersion,
        observation.sceneRevision < sameEvaluator.sceneRevision
      {
        return false
      }
      if observation.bindingVersion == sameEvaluator.bindingVersion,
        observation.sceneRevision == sameEvaluator.sceneRevision,
        observation.frameID < sameEvaluator.frameID
      {
        return false
      }
    }

    guard let latest = latestObservations[id] else { return true }
    if observation.bindingVersion < latest.bindingVersion { return false }
    if observation.bindingVersion > latest.bindingVersion { return true }
    if observation.sceneRevision < latest.sceneRevision { return false }
    if observation.sceneRevision > latest.sceneRevision { return true }
    return latest.frameID - observation.frameID <= max(0, maximumFusionFrameDelta)
  }

  private func accumulateAndFuse(_ observation: Observation, for id: GoalID) -> Observation {
    let latest = latestObservations[id]
    let contextChanged =
      latest.map {
        $0.bindingVersion != observation.bindingVersion
          || $0.sceneRevision != observation.sceneRevision
      } ?? false
    if contextChanged { recentEvidence[id] = [:] }

    recentEvidence[id, default: [:]][observation.evaluator] = observation
    let newestFrame =
      recentEvidence[id, default: [:]].values.map(\.frameID).max()
      ?? observation.frameID
    recentEvidence[id] = recentEvidence[id, default: [:]].filter {
      newestFrame - $0.value.frameID <= max(0, maximumFusionFrameDelta)
    }
    let values = Array(recentEvidence[id, default: [:]].values)
    evaluatorReliability.observe(
      values,
      sceneConditions: sceneConditions,
      registry: reliabilityRegistry
    )
    let result = ObservationFusion(evaluatorTrust: evaluatorTrust)
      .fuseDetailed(
        values,
        allowFrameSkew: maximumFusionFrameDelta,
        reliabilityModel: evaluatorReliability,
        sceneConditions: sceneConditions,
        registry: reliabilityRegistry
      )
    if let report = result?.conflict { latestConflictReports[id] = report }
    return result?.observation ?? observation
  }

  private func update(_ definition: GoalDefinition, with observation: Observation) {
    guard var runtime = states[definition.id] else { return }
    let previousState = runtime.state
    let contextChanged =
      runtime.lastUpdatedFrame != nil
      && (observation.bindingVersion != runtime.lastBindingVersion
        || observation.sceneRevision != runtime.lastSceneRevision)

    if contextChanged {
      runtime.state = .unresolved
      runtime.score = nil
      runtime.enterCounter = 0
      runtime.exitCounter = 0
      runtime.lastHysteresisFrame = nil
      runtime.dirty = true
    }

    runtime.dirty = false
    runtime.confidence = observation.confidence
    runtime.lastUpdatedFrame = observation.frameID
    runtime.lastBindingVersion = observation.bindingVersion
    runtime.lastSceneRevision = observation.sceneRevision

    guard runtime.policy != .skipped else {
      states[definition.id] = runtime
      return
    }

    let dependenciesSatisfied = definition.dependencies.allSatisfy { dependency in
      guard let dependencyState = states[dependency] else { return false }
      return dependencyState.policy == .skipped || dependencyState.state == .satisfied
    }
    guard dependenciesSatisfied else {
      runtime.state = .inactive
      runtime.score = nil
      runtime.enterCounter = 0
      runtime.exitCounter = 0
      runtime.lastHysteresisFrame = nil
      states[definition.id] = runtime
      if previousState != .inactive {
        propagateDependencyState(from: definition.id, satisfied: false)
      }
      return
    }
    if runtime.state == .inactive { runtime.state = .unresolved }

    let confidenceFloor = max(minimumConfidence, definition.minimumConfidence)
    guard observation.confidence >= confidenceFloor else {
      runtime.state = .unknown
      runtime.score = nil
      runtime.enterCounter = 0
      runtime.exitCounter = 0
      runtime.lastHysteresisFrame = nil
      states[definition.id] = runtime
      if previousState == .satisfied {
        propagateDependencyState(from: definition.id, satisfied: false)
      }
      return
    }

    let evaluation = Scoring.evaluate(observation, target: definition.target)
    guard evaluation.state != .unknown else {
      runtime.state = .unknown
      runtime.score = nil
      runtime.enterCounter = 0
      runtime.exitCounter = 0
      runtime.lastHysteresisFrame = nil
      states[definition.id] = runtime
      if previousState == .satisfied {
        propagateDependencyState(from: definition.id, satisfied: false)
      }
      return
    }

    runtime.score = evaluation.score
    let requiredEnterFrames =
      enterFramesOverride > 0 ? enterFramesOverride : definition.stability.enterFrames
    let requiredExitFrames =
      exitFramesOverride > 0 ? exitFramesOverride : definition.stability.exitFrames
    let newHysteresisFrame = runtime.lastHysteresisFrame != observation.frameID

    if runtime.state == .satisfied {
      if evaluation.score < definition.stability.exitThreshold {
        if newHysteresisFrame {
          runtime.exitCounter += 1
        } else if runtime.exitCounter == 0 {
          runtime.exitCounter = 1
        }
        if runtime.exitCounter >= requiredExitFrames {
          runtime.state = .drifted
          runtime.exitCounter = 0
        }
      } else {
        runtime.exitCounter = 0
      }
      runtime.enterCounter = 0
    } else {
      runtime.exitCounter = 0
      if evaluation.score >= definition.stability.enterThreshold {
        if newHysteresisFrame {
          runtime.enterCounter += 1
        } else if runtime.enterCounter == 0 {
          runtime.enterCounter = 1
        }
        if runtime.enterCounter >= requiredEnterFrames {
          runtime.state = .satisfied
          runtime.enterCounter = 0
        }
      } else {
        // Hysteresis protects an already-satisfied goal only. Reliable evidence
        // below the enter threshold is immediately actionable.
        runtime.enterCounter = 0
        runtime.state = .active
      }
    }
    runtime.lastHysteresisFrame = observation.frameID

    states[definition.id] = runtime
    if previousState != runtime.state {
      propagateDependencyState(from: definition.id, satisfied: runtime.state == .satisfied)
    }
  }

  private func propagateDependencyState(from id: GoalID, satisfied: Bool) {
    if satisfied {
      for dependent in graph.directDependents(of: id) {
        guard var state = states[dependent], state.policy != .skipped else { continue }
        state.dirty = true
        let allParentsSatisfied =
          definitions[dependent]?.dependencies.allSatisfy { parent in
            guard let parentState = states[parent] else { return false }
            return parentState.policy == .skipped || parentState.state == .satisfied
          } ?? false
        if allParentsSatisfied, state.state == .inactive { state.state = .unresolved }
        states[dependent] = state
      }
    } else {
      for dependent in graph.dependents(of: id) {
        guard var state = states[dependent], state.policy != .skipped else { continue }
        state.dirty = true
        state.state = .inactive
        state.score = nil
        state.enterCounter = 0
        state.exitCounter = 0
        state.lastHysteresisFrame = nil
        states[dependent] = state
      }
    }
  }
}

private struct ObservationBatchKey: Hashable {
  let bindingVersion: Int
  let sceneRevision: Int
  let frameID: Int
}
