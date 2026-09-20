import Foundation

public struct ControllerMemory: Codable, Equatable, Sendable {
  public var declinePenalty: [ActionID: Int] = [:]
  public var failurePenalty: [ActionID: Int] = [:]
  public var oppositeEffects = 0
  public var fatigue = 0
  public var recentCancels = 0
  public var successfulActions = 0
  public var oscillationEvents = 0
  public var recentMotionSignatures: [MotionSignature] = []
  public var effectModel = SessionEffectModel()

  public init() {}
}

public struct MotionSignature: Codable, Equatable, Sendable {
  public let actor: ActionActor
  public let operation: ActionOperation
  public let direction: ActionDirection
  public let coordinateFrame: CoordinateFrame

  public init(_ action: ActionDefinition) {
    actor = action.actor
    operation = action.operation
    direction = action.direction
    coordinateFrame = action.coordinateFrame
  }
}

public enum UserEvent: Codable, Equatable, Sendable {
  case done
  case anotherWay
  case impossible
  case cancel
  case lock(GoalID)
  case skip(GoalID)
  case satisfied
  case resumeGuidance
}

/// Action selection is deliberately separate from presentation. It owns user
/// constraints, capabilities, safety clearance and short-lived action memory.
public final class ActionPlanner {
  public var constraints = Set<SessionConstraint>()
  public var lockedGoals = Set<GoalID>()
  public var capabilities = Set<String>()
  public var safetyClearances = Set<String>()
  public var memory = ControllerMemory()
  public private(set) var needsReobserve = false

  public init() {}

  public func grantSafetyClearance(for family: String) { safetyClearances.insert(family) }
  public func revokeSafetyClearance(for family: String) { safetyClearances.remove(family) }
  public func clearSafetyClearances() { safetyClearances.removeAll() }

  public func feasible(_ action: ActionDefinition, engine: GoalEngine) -> Bool {
    switch action.safety {
    case .restricted:
      return false
    case .contextDependent:
      guard safetyClearances.contains(action.family) else { return false }
    case .safe:
      break
    }

    guard !constraints.contains(SessionConstraint(family: action.family)) else { return false }
    if let capability = action.requiredCapability, !capabilities.contains(capability) {
      return false
    }
    guard engine.isConditionMet(action.condition) else { return false }

    for effect in action.effects
    where effect.possibleDamage > 0 && lockedGoals.contains(effect.goal) {
      return false
    }
    return true
  }

  public func utility(
    _ action: ActionDefinition,
    engine: GoalEngine,
    goalGroups: [GoalGroupDefinition] = []
  ) -> Double {
    let goalPlanner = GoalSetPlanner()
    let benefit = action.effects.reduce(into: 0.0) { total, effect in
      guard let state = engine.states[effect.goal], state.policy != .skipped else { return }
      let priority = goalPlanner.priority(of: effect.goal, engine: engine, goalGroups: goalGroups)
      total += priority * effect.expectedImprovement

      if effect.possibleDamage > 0, let definition = engine.definitions[effect.goal] {
        let damageWeight: Double =
          switch definition.constraint {
          case .hard: 4.0
          case .core: 2.3
          case .soft: 0.8
          }
        let lockedMultiplier = state.policy == .locked ? 100 : 1
        total -=
          damageWeight * definition.importance * effect.possibleDamage * Double(lockedMultiplier)
      }
    }

    let calibratedBenefit = benefit * memory.effectModel.gainMultiplier(for: action)
    let coverageBonus = sharedCoverageBonus(action, engine: engine, goalGroups: goalGroups)
    let decline = Double(memory.declinePenalty[action.id] ?? 0) * 0.75
    let failure = Double(memory.failurePenalty[action.id] ?? 0) * 0.90
    let learnedUncertainty = memory.effectModel.uncertaintyPenalty(for: action)
    let safetyCost = action.safety == .contextDependent ? 0.12 : 0
    return calibratedBenefit + coverageBonus
      - action.burden - action.risk - action.uncertainty - learnedUncertainty
      - decline - failure - safetyCost
  }

  public func rank(
    _ actions: [ActionDefinition],
    engine: GoalEngine,
    goalGroups: [GoalGroupDefinition] = []
  ) -> [ActionDefinition] {
    actions.filter { feasible($0, engine: engine) }.sorted {
      let left = utility($0, engine: engine, goalGroups: goalGroups)
      let right = utility($1, engine: engine, goalGroups: goalGroups)
      return left == right ? $0.id.rawValue < $1.id.rawValue : left > right
    }
  }

  public func verificationGoals(for action: ActionDefinition, engine: GoalEngine) -> Set<GoalID> {
    guard action.isInformationSeeking else { return action.touchedGoals }
    let relevant = action.informationGoals.filter { id in
      guard let runtime = engine.states[id], runtime.policy != .skipped else { return false }
      if runtime.dirty { return true }
      if (runtime.confidence ?? 0) < 0.80 { return true }
      switch runtime.state {
      case .unknown, .unresolved, .inactive: return true
      case .active, .drifted, .satisfied, .blocked: return false
      }
    }
    return relevant.isEmpty ? action.informationGoals : Set(relevant)
  }

  public func baseline(for action: ActionDefinition, engine: GoalEngine) -> [GoalID: Double] {
    Dictionary(
      uniqueKeysWithValues: action.touchedGoals.compactMap { id in
        engine.score(for: id).map { (id, $0) }
      })
  }

  public func baselineEvidence(for action: ActionDefinition, engine: GoalEngine) -> [GoalID:
    EvidenceStamp]
  {
    let relevantGoals = action.touchedGoals.union(action.informationGoals)
    return Dictionary(
      uniqueKeysWithValues: relevantGoals.compactMap { id in
        guard let observation = engine.observation(for: id) else { return nil }
        return (
          id,
          EvidenceStamp(
            frameID: observation.frameID,
            bindingVersion: observation.bindingVersion,
            sceneRevision: observation.sceneRevision
          )
        )
      })
  }

  public func baselineConfidence(for action: ActionDefinition, engine: GoalEngine) -> [GoalID:
    Double]
  {
    let relevantGoals = action.touchedGoals.union(action.informationGoals)
    return Dictionary(
      uniqueKeysWithValues: relevantGoals.compactMap { id in
        engine.states[id]?.confidence.map { (id, $0) }
      })
  }

  public func recordProposal(_ action: ActionDefinition) {
    guard action.operation == .move || action.operation == .rotate || action.operation == .reframe
    else {
      return
    }
    let signature = MotionSignature(action)
    if memory.recentMotionSignatures.last == signature { return }
    memory.recentMotionSignatures.append(signature)
    if memory.recentMotionSignatures.count > 6 {
      memory.recentMotionSignatures.removeFirst(memory.recentMotionSignatures.count - 6)
    }

    guard memory.recentMotionSignatures.count >= 4 else { return }
    let last = Array(memory.recentMotionSignatures.suffix(4))
    if areInverse(last[0], last[1]), last[0] == last[2], last[1] == last[3] {
      memory.oscillationEvents += 1
      memory.fatigue += 2
    }
  }

  public func recordDecline(_ action: ActionDefinition) {
    memory.declinePenalty[action.id, default: 0] += 1
    memory.fatigue += 1
  }

  public func recordImpossible(_ action: ActionDefinition) {
    constraints.insert(SessionConstraint(family: action.family))
    safetyClearances.remove(action.family)
    memory.fatigue += 1
  }

  public func recordCancel() {
    needsReobserve = true
    memory.recentCancels += 1
    memory.fatigue += 1
  }

  public func requestVerification() { needsReobserve = true }
  public func clearReobserveRequest() { needsReobserve = false }

  public func recordVerification(_ result: ActionVerification, action: ActionDefinition) {
    memory.effectModel.record(result, for: action)
    switch result {
    case .improved:
      memory.failurePenalty[action.id] = 0
      memory.oppositeEffects = max(0, memory.oppositeEffects - 1)
      memory.successfulActions += 1
      memory.fatigue = max(0, memory.fatigue - 1)
    case .partial:
      memory.failurePenalty[action.id] = max(0, (memory.failurePenalty[action.id] ?? 0) - 1)
    case .noEffect:
      memory.failurePenalty[action.id, default: 0] += 1
      memory.fatigue += 1
    case .oppositeEffect:
      memory.failurePenalty[action.id, default: 0] += 1
      memory.oppositeEffects += 1
      memory.fatigue += 2
    case .inconclusive:
      break
    }
  }

  private func areInverse(_ lhs: MotionSignature, _ rhs: MotionSignature) -> Bool {
    guard lhs.actor == rhs.actor, lhs.operation == rhs.operation,
      lhs.coordinateFrame == rhs.coordinateFrame
    else { return false }
    switch (lhs.direction, rhs.direction) {
    case (.left, .right), (.right, .left),
      (.up, .down), (.down, .up),
      (.forward, .backward), (.backward, .forward),
      (.towardCamera, .awayFromCamera), (.awayFromCamera, .towardCamera):
      return true
    default:
      return false
    }
  }

  private func sharedCoverageBonus(
    _ action: ActionDefinition,
    engine: GoalEngine,
    goalGroups: [GoalGroupDefinition]
  ) -> Double {
    let affectedCritical = action.improvedGoals.compactMap { id -> Double? in
      guard let definition = engine.definitions[id],
        definition.constraint != .soft,
        let runtime = engine.states[id],
        runtime.policy != .skipped,
        runtime.state == .active || runtime.state == .drifted
      else { return nil }
      return GoalSetPlanner().priority(of: id, engine: engine, goalGroups: goalGroups)
    }
    guard affectedCritical.count > 1 else { return 0 }
    // Small explicit bonus for one intervention solving a shared root cause.
    // The base benefit still dominates, so a broad but weak action cannot win
    // purely because it touches many goals.
    let average = affectedCritical.reduce(0, +) / Double(affectedCritical.count)
    return min(0.35, Double(affectedCritical.count - 1) * 0.06 * average)
  }

  public func resetInteractionPressure() {
    memory.fatigue = 0
    memory.recentCancels = 0
    memory.oppositeEffects = 0
    memory.oscillationEvents = 0
    memory.recentMotionSignatures.removeAll()
  }
}
