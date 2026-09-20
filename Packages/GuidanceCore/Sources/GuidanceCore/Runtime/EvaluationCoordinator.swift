import Foundation

public struct EvaluationBudgetPolicy: Codable, Equatable, Sendable {
  public var localGuardInterval = 1
  public var localFocusInterval = 2
  public var localWatchInterval = 12
  public var semanticGuardInterval = 4
  public var semanticFocusInterval = 6
  public var semanticWatchInterval = 24

  public init() {}
}

/// Stateful cadence, resource-budget and evaluator-health gate layered on top
/// of EvaluationPlanner. HARD guards are never dropped merely to satisfy a
/// slot cap; optional focus/watch work is shed first under pressure.
public struct EvaluationCoordinator: Sendable {
  public var planner: EvaluationPlanner
  public var budget: EvaluationBudgetPolicy
  public var resourcePressure: RuntimeResourcePressure = .nominal
  public var evaluatorHealth = EvaluatorHealthMonitor()

  private var lastLocalFrame = [GoalID: Int]()
  private var lastSemanticFrame = [GoalID: Int]()
  private var invalidatedGoals = Set<GoalID>()

  public init(
    planner: EvaluationPlanner = .init(),
    budget: EvaluationBudgetPolicy = .init(),
    resourcePressure: RuntimeResourcePressure = .nominal,
    evaluatorHealth: EvaluatorHealthMonitor = .init()
  ) {
    self.planner = planner
    self.budget = budget
    self.resourcePressure = resourcePressure
    self.evaluatorHealth = evaluatorHealth
  }

  public mutating func reset() {
    lastLocalFrame.removeAll()
    lastSemanticFrame.removeAll()
    invalidatedGoals.removeAll()
    evaluatorHealth.reset()
  }

  public mutating func resetCadenceOnly() {
    lastLocalFrame.removeAll()
    lastSemanticFrame.removeAll()
    invalidatedGoals.removeAll()
  }

  public mutating func updateResourcePressure(_ pressure: RuntimeResourcePressure) {
    resourcePressure = pressure
  }

  public mutating func recordEvaluatorSuccess(_ evaluator: EvaluatorID, frameID: Int) {
    evaluatorHealth.recordSuccess(evaluator, frameID: frameID)
  }

  public mutating func recordEvaluatorFailure(
    _ evaluator: EvaluatorID,
    kind: EvaluatorFaultKind,
    frameID: Int
  ) {
    evaluatorHealth.recordFailure(evaluator, kind: kind, frameID: frameID)
  }

  public mutating func invalidate(_ goals: Set<GoalID>, engine: GoalEngine? = nil) {
    invalidatedGoals.formUnion(goals)
    if let engine {
      for goal in goals { invalidatedGoals.formUnion(engine.graph.dependents(of: goal)) }
    }
  }

  public mutating func note(action: ActionDefinition, engine: GoalEngine) {
    invalidate(action.touchedGoals.union(action.informationGoals), engine: engine)
  }

  public mutating func plan(
    frameID: Int,
    engine: GoalEngine,
    registry: GuidanceRegistry
  ) -> EvaluationPlan {
    let available = Set(
      registry.evaluators.keys.filter { evaluatorHealth.isSchedulable($0, frameID: frameID) }
    )
    let base = planner.plan(
      engine: engine,
      registry: registry,
      availableEvaluators: available
    )
    let profile = RuntimeBudgetProfile.profile(for: resourcePressure)

    var local = base.local.filter {
      shouldRun($0, frameID: frameID, semantic: false, profile: profile)
    }
    var semantic = base.semantic.filter {
      shouldRun($0, frameID: frameID, semantic: true, profile: profile)
    }
    if !profile.allowSemanticWatch {
      semantic.removeAll { $0.cadence == .watch }
    }

    local = limited(local, maxSlots: profile.maxLocalSlotsPerFrame)
    semantic = limited(semantic, maxSlots: profile.maxSemanticSlotsPerFrame)

    for slot in local { lastLocalFrame[slot.goalID] = frameID }
    for slot in semantic { lastSemanticFrame[slot.goalID] = frameID }
    invalidatedGoals.subtract(Set(local.map(\.goalID)))
    invalidatedGoals.subtract(Set(semantic.map(\.goalID)))

    return EvaluationPlan(local: local, semantic: semantic)
  }

  private func shouldRun(
    _ slot: EvaluationSlot,
    frameID: Int,
    semantic: Bool,
    profile: RuntimeBudgetProfile
  ) -> Bool {
    if invalidatedGoals.contains(slot.goalID) { return true }
    let last = semantic ? lastSemanticFrame[slot.goalID] : lastLocalFrame[slot.goalID]
    guard let last else { return true }
    if frameID <= last { return false }
    let baseInterval: Int
    switch (semantic, slot.cadence) {
    case (false, .guardFast): baseInterval = budget.localGuardInterval
    case (false, .focus): baseInterval = budget.localFocusInterval
    case (false, .watch): baseInterval = budget.localWatchInterval
    case (true, .guardFast): baseInterval = budget.semanticGuardInterval
    case (true, .focus): baseInterval = budget.semanticFocusInterval
    case (true, .watch): baseInterval = budget.semanticWatchInterval
    }
    let multiplier = slot.cadence == .guardFast ? 1 : profile.intervalMultiplier
    return frameID - last >= max(1, baseInterval * multiplier)
  }

  /// Keeps every guard slot even if it exceeds the nominal cap. Focus/watch
  /// slots fill only the remaining capacity, preserving safety semantics.
  private func limited(_ slots: [EvaluationSlot], maxSlots: Int) -> [EvaluationSlot] {
    let guards = slots.filter { $0.cadence == .guardFast }
    guard maxSlots > guards.count else { return guards }
    let remaining = slots.filter { $0.cadence != .guardFast }
    return guards + Array(remaining.prefix(max(0, maxSlots - guards.count)))
  }
}
