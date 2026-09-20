import Foundation

public enum CaptureState: String, Codable, Sendable {
  case unknown
  case notReady
  case improvable
  case ready
  case readyByUser
  case paused
  case unreachable
  case notApplicable
}

public enum Conformance: String, Codable, Sendable {
  case full
  case high
  case partial
  case low
  case notApplicable
}

public struct Readiness: Equatable, Sendable {
  public let state: CaptureState
  public let conformance: Conformance
  public init(state: CaptureState, conformance: Conformance) {
    self.state = state
    self.conformance = conformance
  }
}

/// Stateful orchestration layer around the pure goal/scheduler/planner pieces.
/// It owns one capture session and is intentionally not Sendable; callers must
/// serialize access (the iOS app does so from MainActor).
public final class GuidanceSession {
  public let engine: GoalEngine
  public let planner: ActionPlanner
  public var scheduler: GuidanceScheduler
  public var verifier = ActionVerifier()
  public var sequencePlanner = ActionSequencePlanner()
  public let actions: [ActionDefinition]
  public let goalGroups: [GoalGroupDefinition]
  public let registry: GuidanceRegistry?
  public var observationValidator = ObservationValidator()
  public var invariantChecker = RuntimeInvariantChecker()

  public private(set) var currentTransaction: ActionInstance?
  public private(set) var activePlan: ActionPlanRuntime?
  public private(set) var lastAction: ActionInstance?
  public private(set) var captureState: CaptureState = .unknown
  public private(set) var conformance: Conformance = .low
  public private(set) var userSatisfied = false
  public private(set) var lastObservedFrame = 0
  public private(set) var verificationRequestedAfterFrame: Int?
  public private(set) var trace: [SessionTraceEvent] = []
  public private(set) var rejectedObservations = 0
  public private(set) var replayEvents: [GuidanceReplayEvent] = []
  public var replayCapacity = 4096
  public var isReplayRecordingEnabled = true
  public private(set) var tickSequence = 0
  public private(set) var runtimePauseReason: RuntimePauseReason?
  public var traceCapacity = 256
  /// Verification must never hold the controller indefinitely when an expected
  /// dimension becomes temporarily unobservable after a user action.
  public var verificationFrameTimeout = 12

  private var traceSequence = 0

  public init(
    goals: [GoalDefinition],
    actions: [ActionDefinition],
    goalGroups: [GoalGroupDefinition] = [],
    registry: GuidanceRegistry? = nil
  ) {
    self.registry = registry
    engine = GoalEngine(goals)
    if let registry {
      let defaults = Dictionary(
        uniqueKeysWithValues: registry.evaluators.values.map {
          ($0.id, $0.defaultReliability)
        })
      engine.evaluatorTrust = defaults
      engine.reliabilityRegistry = registry
      engine.evaluatorReliability = EvaluatorReliabilityModel(baseReliability: defaults)
    }
    planner = ActionPlanner()
    scheduler = GuidanceScheduler()
    self.actions = actions
    self.goalGroups = goalGroups
    refreshConformance()
    appendTrace(.lifecycle, detail: "session.created")
  }

  @discardableResult
  public func ingest(_ observation: Observation) -> [GoalID] {
    appendReplay(.observation(observation))
    guard validateObservation(observation) else {
      completeVerificationIfPossible()
      refreshConformance()
      return []
    }
    advanceFrameClock(observation.frameID)
    let updated = engine.ingest(observation)
    if !updated.isEmpty {
      appendTrace(
        .observation,
        frameID: observation.frameID,
        detail:
          "accepted:\(observation.dimension.rawValue):\(updated.map(\.rawValue).joined(separator: ","))"
      )
      traceConflicts(for: updated, frameID: observation.frameID)
    }
    completeVerificationIfPossible()
    refreshConformance()
    return updated
  }

  @discardableResult
  public func ingestBatch(_ observations: [Observation]) -> [GoalID] {
    appendReplay(.batch(observations))
    let accepted = observations.filter(validateObservation)
    if let frame = accepted.map(\.frameID).max() { advanceFrameClock(frame) }
    let updated = engine.ingestBatch(accepted)
    if let frame = accepted.map(\.frameID).max(), !updated.isEmpty {
      appendTrace(.observation, frameID: frame, detail: "batch.accepted:\(updated.count)")
      traceConflicts(for: updated, frameID: frame)
    }
    completeVerificationIfPossible()
    refreshConformance()
    return updated
  }

  /// Records a processed frame that produced no usable observations.
  /// Frames that do have observations should use `ingestBatch` so all evidence
  /// from that frame is applied atomically before verification timeout checks.
  /// Never pulse this for raw camera frames that were dropped by perception.
  public func advanceFrame(_ frameID: Int) {
    guard frameID >= 0 else { return }
    appendReplay(.frame(frameID))
    advanceFrameClock(frameID)
    completeVerificationIfPossible()
  }

  public func handle(_ event: UserEvent) {
    appendReplay(.user(event))
    appendTrace(.userEvent, detail: eventDescription(event))
    switch event {
    case .done:
      guard var transaction = currentTransaction else { return }
      transaction.state = .verifyRequested
      currentTransaction = transaction
      invalidateEvidence(for: transaction.verificationGoals)
      planner.requestVerification()
      verificationRequestedAfterFrame = lastObservedFrame

    case .anotherWay:
      guard var transaction = currentTransaction else { return }
      abortActivePlan(as: .superseded, reason: "user.anotherWay")
      planner.recordDecline(transaction.definition)
      transaction.state = .declined
      lastAction = transaction
      currentTransaction = nil
      clearPendingVerification()

    case .impossible:
      guard var transaction = currentTransaction else { return }
      abortActivePlan(as: .failed, reason: "user.impossible")
      planner.recordImpossible(transaction.definition)
      transaction.state = .blocked
      lastAction = transaction
      currentTransaction = nil
      clearPendingVerification()
      appendTrace(.constraint, detail: "blocked.family:\(transaction.definition.family)")

    case .cancel:
      abortActivePlan(as: .cancelled, reason: "user.cancel")
      if var transaction = currentTransaction {
        transaction.state = .cancelled
        lastAction = transaction
        invalidateEvidence(for: transaction.verificationGoals)
      }
      currentTransaction = nil
      verificationRequestedAfterFrame = lastObservedFrame
      planner.recordCancel()

    case .lock(let goalID):
      if activePlan?.definition.steps.contains(where: { step in
        step.effects.contains(where: { $0.goal == goalID && $0.possibleDamage > 0 })
      }) == true {
        abortActivePlan(as: .superseded, reason: "goal.locked:\(goalID.rawValue)")
      }
      if let transaction = currentTransaction,
        transaction.definition.effects.contains(where: {
          $0.goal == goalID && $0.possibleDamage > 0
        })
      {
        var cancelled = transaction
        cancelled.state = .cancelled
        lastAction = cancelled
        currentTransaction = nil
        clearPendingVerification()
      }
      planner.lockedGoals.insert(goalID)
      engine.setPolicy(.locked, for: goalID)

    case .skip(let goalID):
      guard engine.definitions[goalID]?.skippable == true else { return }
      if activePlan?.definition.steps.contains(where: { $0.touchedGoals.contains(goalID) }) == true
      {
        abortActivePlan(as: .superseded, reason: "goal.skipped:\(goalID.rawValue)")
      }
      engine.setPolicy(.skipped, for: goalID)
      if let transaction = currentTransaction,
        transaction.definition.touchedGoals.contains(goalID)
          || transaction.definition.informationGoals.contains(goalID)
      {
        var cancelled = transaction
        cancelled.state = .cancelled
        lastAction = cancelled
        currentTransaction = nil
        clearPendingVerification()
      }

    case .satisfied:
      abortActivePlan(as: .cancelled, reason: "user.satisfied")
      userSatisfied = true
      if var transaction = currentTransaction {
        transaction.state = .cancelled
        lastAction = transaction
      }
      currentTransaction = nil
      clearPendingVerification()

    case .resumeGuidance:
      activePlan = nil
      userSatisfied = false
      planner.resetInteractionPressure()
    }
    refreshConformance()
  }

  @discardableResult
  public func tick() -> SchedulerDecision {
    appendReplay(.tick)
    tickSequence += 1
    if runtimePauseReason != nil {
      captureState = .paused
      currentTransaction = nil
      activePlan = nil
      let decision = SchedulerDecision.paused
      appendTrace(.decision, detail: "runtime.paused")
      refreshConformance()
      return decision
    }
    // Continue a validated short-horizon plan before asking the ordinary
    // scheduler to re-optimize. This is the only place where temporary CORE/
    // SOFT regressions may be tolerated between verified steps. HARD guards
    // always preempt the plan.
    if currentTransaction == nil, let step = activePlan?.currentStep {
      if canContinueActivePlan(with: step) {
        return applyProposal(step, source: "plan.continue")
      }
      abortActivePlan(as: .superseded, reason: "plan.invalidated")
    }

    let stickyAction: ActionDefinition?
    if let transaction = currentTransaction, transaction.state == .proposed {
      stickyAction = transaction.definition
    } else {
      stickyAction = nil
    }

    var decision = scheduler.decide(
      engine: engine,
      planner: planner,
      actions: actions,
      goalGroups: goalGroups,
      currentAction: stickyAction,
      userSatisfied: userSatisfied
    )

    // The one-step scheduler remains the safety/readiness gate. Only after it
    // decides that an action is appropriate do we allow bounded look-ahead to
    // replace that action with the first step of a demonstrably better plan.
    if case .propose(let scheduledFirst) = decision, currentTransaction == nil, activePlan == nil,
      let plan = sequencePlanner.bestPlan(
        engine: engine, planner: planner, actions: actions, goalGroups: goalGroups,
        startingWith: scheduledFirst),
      let first = plan.steps.first
    {
      activePlan = ActionPlanRuntime(plan)
      appendTrace(
        .decision,
        detail:
          "plan.selected:\(plan.id.rawValue):\(plan.steps.map(\.id.rawValue).joined(separator: ">"))"
      )
      decision = .propose(first)
    } else if case .unreachable = decision, currentTransaction == nil, activePlan == nil,
      !hasActiveHardFailure(),
      let plan = sequencePlanner.bestPlan(
        engine: engine, planner: planner, actions: actions, goalGroups: goalGroups),
      let first = plan.steps.first
    {
      // A bounded plan may legitimately start with a temporarily costly CORE
      // move that the one-step scheduler would reject, provided no HARD guard
      // is currently failing. This is how we support "move back, then zoom"-
      // style transactions without weakening safety/guard semantics.
      activePlan = ActionPlanRuntime(plan)
      appendTrace(
        .decision,
        detail:
          "plan.rescuedUnreachable:\(plan.id.rawValue):\(plan.steps.map(\.id.rawValue).joined(separator: ">"))"
      )
      decision = .propose(first)
    }

    switch decision {
    case .propose(let action):
      return applyProposal(action, source: activePlan == nil ? "scheduler" : "plan.start")
    case .requestEvidence:
      captureState = .unknown
      currentTransaction = nil
    case .wait:
      captureState = .notReady
    case .ready:
      captureState = .ready
      currentTransaction = nil
      activePlan = nil
    case .readyByUser:
      captureState = .readyByUser
      currentTransaction = nil
      activePlan = nil
    case .paused:
      captureState = .paused
      currentTransaction = nil
      activePlan = nil
    case .unreachable:
      captureState = .unreachable
      currentTransaction = nil
      activePlan = nil
    case .unknown:
      captureState = .unknown
      currentTransaction = nil
    }

    appendTrace(.decision, detail: decisionDescription(decision))
    refreshConformance()
    return decision
  }

  private func applyProposal(_ action: ActionDefinition, source: String) -> SchedulerDecision {
    captureState = .improvable
    if currentTransaction?.definition.id != action.id {
      planner.recordProposal(action)
      currentTransaction = ActionInstance(
        action,
        baselineScores: planner.baseline(for: action, engine: engine),
        baselineEvidence: planner.baselineEvidence(for: action, engine: engine),
        baselineConfidence: planner.baselineConfidence(for: action, engine: engine),
        verificationGoals: planner.verificationGoals(for: action, engine: engine)
      )
    }
    let decision = SchedulerDecision.propose(action)
    appendTrace(.decision, detail: "\(source):\(action.id.rawValue)")
    refreshConformance()
    return decision
  }

  private func hasActiveHardFailure() -> Bool {
    engine.states.contains { id, runtime in
      guard engine.definitions[id]?.constraint == .hard, runtime.policy != .skipped else {
        return false
      }
      switch runtime.state {
      case .satisfied: return false
      default: return true
      }
    }
  }

  private func canContinueActivePlan(with step: ActionDefinition) -> Bool {
    guard planner.feasible(step, engine: engine) else { return false }
    let blockingHard = engine.states.contains { id, runtime in
      guard engine.definitions[id]?.constraint == .hard, runtime.policy != .skipped else {
        return false
      }
      let failed =
        runtime.state == .active || runtime.state == .drifted || runtime.state == .unknown
        || runtime.state == .unresolved || runtime.state == .inactive || runtime.state == .blocked
      return failed && !step.improvedGoals.contains(id)
    }
    return !blockingHard
  }

  private func abortActivePlan(as state: ActionPlanState, reason: String) {
    guard var plan = activePlan else { return }
    plan.state = state
    appendTrace(
      .decision,
      detail: "plan.terminated:\(plan.definition.id.rawValue):\(state.rawValue):\(reason)")
    activePlan = nil
  }

  /// Runs one controller decision tick and returns an auditable report that
  /// exposes the frozen phase order, current work sets, decision and invariant
  /// status. The ordinary `tick()` API remains the source of state mutation.
  @discardableResult
  public func tickDetailed() -> RuntimeTickReport {
    let decision = tick()
    let workSets = GoalSetPlanner().classify(engine: engine)
    return RuntimeTickReport(
      sequence: tickSequence,
      phases: RuntimeTickPhase.allCases,
      workSets: workSets,
      decision: ReplayDecision(decision),
      readiness: readiness(),
      invariantIssues: invariantIssues()
    )
  }

  /// Updates sensing-context quality without turning those conditions into
  /// user-facing photography goals. This context only changes temporary
  /// evaluator trust and is recorded for deterministic replay.
  public func updateSceneConditions(_ profile: SceneConditionProfile?) {
    guard engine.sceneConditions != profile else { return }
    engine.sceneConditions = profile
    appendReplay(.sceneConditions(profile))
    if let profile {
      let severe = profile.severities
        .filter { $0.value >= 0.5 }
        .sorted { $0.key.rawValue < $1.key.rawValue }
        .map { "\($0.key.rawValue)=\(String(format: "%.2f", $0.value))" }
        .joined(separator: ",")
      appendTrace(
        .observation,
        frameID: profile.frameID,
        detail: severe.isEmpty ? "scene.conditions.clear" : "scene.conditions:\(severe)"
      )
    } else {
      appendTrace(.observation, detail: "scene.conditions.reset")
    }
  }

  public func pauseRuntime(_ reason: RuntimePauseReason) {
    appendReplay(.runtimePause(reason))
    abortActivePlan(as: .cancelled, reason: "runtime.pause:\(reason.rawValue)")
    if var transaction = currentTransaction {
      transaction.state = .cancelled
      lastAction = transaction
    }
    currentTransaction = nil
    verificationRequestedAfterFrame = nil
    planner.clearReobserveRequest()
    runtimePauseReason = reason
    captureState = .paused
    appendTrace(.fault, detail: "runtime.pause:\(reason.rawValue)")
    refreshConformance()
  }

  /// Resuming never trusts the pre-interruption scene. Policies and learned
  /// session calibration survive, but every photography goal must be observed
  /// again before READY can be reached.
  public func resumeRuntime() {
    appendReplay(.runtimeResume)
    guard runtimePauseReason != nil else { return }
    let policies = Dictionary(uniqueKeysWithValues: engine.states.map { ($0.key, $0.value.policy) })
    engine.resetRuntimeEvidence(preservingPolicies: policies)
    currentTransaction = nil
    activePlan = nil
    verificationRequestedAfterFrame = nil
    lastObservedFrame = 0
    runtimePauseReason = nil
    captureState = .unknown
    planner.clearReobserveRequest()
    appendTrace(.lifecycle, detail: "runtime.resumed.reobserve")
    refreshConformance()
  }

  private func definitionSignature() -> SessionDefinitionSignature {
    SessionDefinitionSignature(
      goals: Array(engine.definitions.values),
      actions: actions,
      goalGroups: goalGroups,
      registry: registry
    )
  }

  public func checkpoint() -> GuidanceSessionCheckpoint {
    let signature = definitionSignature()
    let policies = Dictionary(uniqueKeysWithValues: engine.states.map { ($0.key, $0.value.policy) })
    let checkpoint = GuidanceSessionCheckpoint(
      signature: signature,
      goalPolicies: policies,
      planner: PlannerCheckpoint(
        constraints: planner.constraints,
        lockedGoals: planner.lockedGoals,
        memory: planner.memory
      ),
      evaluatorReliability: engine.evaluatorReliability,
      sourceFrameID: lastObservedFrame
    )
    appendTrace(.checkpoint, frameID: lastObservedFrame, detail: "checkpoint.created")
    return checkpoint
  }

  /// Restores only session-local preferences/calibration. Transient camera
  /// evidence, safety clearance, device capabilities, active actions and plans
  /// are intentionally not restored because their physical context may have
  /// changed while the app was suspended.
  @discardableResult
  public func restore(from checkpoint: GuidanceSessionCheckpoint) -> CheckpointRestoreResult {
    guard checkpoint.schemaVersion == 1 || checkpoint.schemaVersion == 2 else {
      appendTrace(.checkpoint, detail: "checkpoint.rejected.schema")
      return .rejectedSchema
    }
    let expected = definitionSignature()
    let definitionMatches =
      checkpoint.schemaVersion == 1
      ? checkpoint.signature.matchesLegacyStructure(expected)
      : checkpoint.signature == expected
    guard definitionMatches else {
      appendTrace(.checkpoint, detail: "checkpoint.rejected.definitionMismatch")
      return .rejectedDefinitionMismatch
    }

    var safePolicies = [GoalID: UserGoalPolicy]()
    for (id, definition) in engine.definitions {
      let requested = checkpoint.goalPolicies[id] ?? .normal
      safePolicies[id] = requested == .skipped && !definition.skippable ? .normal : requested
    }
    engine.resetRuntimeEvidence(preservingPolicies: safePolicies)
    engine.evaluatorReliability = checkpoint.evaluatorReliability.sanitized(for: registry)

    planner.constraints = checkpoint.planner.constraints
    planner.lockedGoals = checkpoint.planner.lockedGoals.filter { safePolicies[$0] == .locked }
    planner.memory = checkpoint.planner.memory
    planner.capabilities.removeAll()
    planner.clearSafetyClearances()
    planner.clearReobserveRequest()

    currentTransaction = nil
    activePlan = nil
    lastAction = nil
    verificationRequestedAfterFrame = nil
    userSatisfied = false
    lastObservedFrame = 0
    runtimePauseReason = nil
    captureState = .unknown
    appendTrace(
      .checkpoint,
      detail: "checkpoint.restored:sourceFrame=\(checkpoint.sourceFrameID):reobserve"
    )
    appendReplay(.restore(checkpoint))
    refreshConformance()
    return .restored
  }

  public func readiness() -> Readiness { Readiness(state: captureState, conformance: conformance) }
  public func canSkip(_ goalID: GoalID) -> Bool { engine.definitions[goalID]?.skippable == true }

  public func invariantIssues() -> [RuntimeInvariantIssue] {
    invariantChecker.check(
      engine: engine,
      planner: planner,
      currentAction: currentTransaction,
      activePlan: activePlan,
      verificationRequestedAfterFrame: verificationRequestedAfterFrame,
      userSatisfied: userSatisfied,
      runtimePauseReason: runtimePauseReason,
      captureState: captureState
    )
  }

  public func updateCapabilities(_ capabilities: Set<String>) {
    guard planner.capabilities != capabilities else { return }
    planner.capabilities = capabilities
    appendReplay(.capabilities(capabilities))
    appendTrace(
      .lifecycle,
      detail: "capabilities.updated:\(capabilities.sorted().joined(separator: ","))"
    )
  }

  public func grantSafetyClearance(for actionFamily: String) {
    guard !planner.safetyClearances.contains(actionFamily) else { return }
    planner.grantSafetyClearance(for: actionFamily)
    appendReplay(.safetyClearance(family: actionFamily, granted: true))
    appendTrace(.constraint, detail: "safety.granted:\(actionFamily)")
  }

  public func revokeSafetyClearance(for actionFamily: String) {
    guard planner.safetyClearances.contains(actionFamily) else { return }
    planner.revokeSafetyClearance(for: actionFamily)
    appendReplay(.safetyClearance(family: actionFamily, granted: false))
    appendTrace(.constraint, detail: "safety.revoked:\(actionFamily)")
  }

  public func snapshot() -> GuidanceSnapshot {
    GuidanceSnapshot(
      captureState: captureState,
      conformance: conformance,
      currentActionID: currentTransaction?.definition.id,
      currentActionState: currentTransaction?.state,
      activePlanID: activePlan?.definition.id,
      activePlanState: activePlan?.state,
      activePlanStepIndex: activePlan?.stepIndex,
      verificationPending: planner.needsReobserve || verificationRequestedAfterFrame != nil,
      userSatisfied: userSatisfied,
      capabilities: planner.capabilities,
      constraints: planner.constraints,
      safetyClearances: planner.safetyClearances,
      tickSequence: tickSequence,
      goalStates: engine.states,
      memory: ControllerMemorySnapshot(
        fatigue: planner.memory.fatigue,
        recentCancels: planner.memory.recentCancels,
        oppositeEffects: planner.memory.oppositeEffects,
        successfulActions: planner.memory.successfulActions
      ),
      lastObservedFrame: lastObservedFrame,
      rejectedObservations: rejectedObservations,
      evaluatorReliability: engine.evaluatorReliability.states
        .map { key, state in
          EvaluatorReliabilitySnapshot(
            evaluator: key.evaluator, dimension: key.dimension, reliability: state.reliability,
            sampleCount: state.sampleCount, conflictCount: state.conflictCount)
        }
        .sorted { lhs, rhs in
          lhs.evaluator.rawValue == rhs.evaluator.rawValue
            ? lhs.dimension.rawValue < rhs.dimension.rawValue
            : lhs.evaluator.rawValue < rhs.evaluator.rawValue
        },
      conflicts: engine.latestConflictReports
        .map { goal, report in GoalConflictSnapshot(goal: goal, report: report) }
        .sorted { $0.goal.rawValue < $1.goal.rawValue },
      sceneConditions: engine.sceneConditions,
      runtimePauseReason: runtimePauseReason
    )
  }

  private func traceConflicts(for goals: [GoalID], frameID: Int) {
    for goalID in goals {
      guard let report = engine.latestConflictReports[goalID], report.level != .none else {
        continue
      }
      appendTrace(
        .validation,
        frameID: frameID,
        detail:
          "evaluator.conflict:\(goalID.rawValue):\(report.level.rawValue):agreement=\(String(format: "%.3f", report.agreement)):dominance=\(String(format: "%.3f", report.strongestShare))"
      )
    }
  }

  /// Clears all session-local user choices. Recipe author policy remains intact.
  public func resetUserOverrides() {
    appendReplay(.resetUserOverrides)
    userSatisfied = false
    currentTransaction = nil
    activePlan = nil
    clearPendingVerification()
    planner.resetInteractionPressure()
    planner.constraints.removeAll()
    planner.lockedGoals.removeAll()
    planner.clearSafetyClearances()
    for id in engine.states.keys { engine.setPolicy(.normal, for: id) }
    appendTrace(.lifecycle, detail: "session.overrides.reset")
    refreshConformance()
  }

  private func advanceFrameClock(_ frameID: Int) {
    guard frameID >= 0 else { return }
    lastObservedFrame = max(lastObservedFrame, frameID)
  }

  private func clearPendingVerification() {
    verificationRequestedAfterFrame = nil
    planner.clearReobserveRequest()
  }

  private func validateObservation(_ observation: Observation) -> Bool {
    guard let registry else { return true }
    let issues = observationValidator.validate(observation, registry: registry)
    for issue in issues {
      appendTrace(
        .validation,
        frameID: observation.frameID,
        detail: "\(issue.severity.rawValue):\(issue.rule.rawValue):\(issue.message)"
      )
    }
    let rejected = issues.contains { $0.severity == .error }
    if rejected { rejectedObservations += 1 }
    return !rejected
  }

  private func invalidateEvidence(for goals: Set<GoalID>) {
    for goalID in goals {
      engine.markDirty(goalID)
      engine.propagateDirty(from: goalID)
    }
  }

  private func completeVerificationIfPossible() {
    guard let requestedFrame = verificationRequestedAfterFrame,
      var transaction = currentTransaction,
      transaction.state == .verifyRequested
    else {
      if planner.needsReobserve,
        let requestedFrame = verificationRequestedAfterFrame,
        lastObservedFrame > requestedFrame,
        currentTransaction == nil
      {
        planner.clearReobserveRequest()
        verificationRequestedAfterFrame = nil
      }
      return
    }

    let affected = transaction.verificationGoals
    let allUpdated = affected.allSatisfy { id in
      guard let frame = engine.states[id]?.lastUpdatedFrame else { return false }
      return frame > requestedFrame
    }
    if !allUpdated {
      guard lastObservedFrame - requestedFrame >= max(1, verificationFrameTimeout) else { return }
      transaction.verification = .inconclusive
      transaction.state = .failed
      planner.recordVerification(.inconclusive, action: transaction.definition)
      appendTrace(
        .verification,
        frameID: lastObservedFrame,
        detail: "\(transaction.definition.id.rawValue):timeout.inconclusive"
      )
      if activePlan?.currentStep?.id == transaction.definition.id {
        abortActivePlan(as: .failed, reason: "verification.inconclusive")
      }
      lastAction = transaction
      currentTransaction = nil
      planner.clearReobserveRequest()
      verificationRequestedAfterFrame = nil
      return
    }

    let result = verifier.verify(transaction, engine: engine)
    transaction.verification = result
    switch result {
    case .improved: transaction.state = .completed
    case .partial: transaction.state = .partial
    case .noEffect, .oppositeEffect, .inconclusive: transaction.state = .failed
    }
    planner.recordVerification(result, action: transaction.definition)
    appendTrace(
      .verification, frameID: lastObservedFrame,
      detail: "\(transaction.definition.id.rawValue):\(result.rawValue)")
    updateActivePlan(after: transaction, result: result)
    lastAction = transaction
    currentTransaction = nil
    planner.clearReobserveRequest()
    verificationRequestedAfterFrame = nil
  }

  private func updateActivePlan(after transaction: ActionInstance, result: ActionVerification) {
    guard var plan = activePlan, plan.currentStep?.id == transaction.definition.id else { return }
    switch result {
    case .improved, .partial:
      if plan.isLastStep {
        plan.state = .completed
        appendTrace(
          .verification, frameID: lastObservedFrame,
          detail: "plan.completed:\(plan.definition.id.rawValue)")
        activePlan = nil
      } else {
        plan.state = .executing
        plan.stepIndex += 1
        activePlan = plan
        appendTrace(
          .verification, frameID: lastObservedFrame,
          detail: "plan.advance:\(plan.definition.id.rawValue):\(plan.stepIndex)")
      }
    case .noEffect, .oppositeEffect, .inconclusive:
      plan.state = .failed
      appendTrace(
        .verification, frameID: lastObservedFrame,
        detail: "plan.failed:\(plan.definition.id.rawValue):\(result.rawValue)")
      activePlan = nil
    }
  }

  private func refreshConformance() {
    guard !engine.states.isEmpty else {
      conformance = .notApplicable
      return
    }
    var weightedTotal = 0.0
    var weightedQuality = 0.0
    var skippedCount = 0

    for (id, state) in engine.states {
      guard let definition = engine.definitions[id] else { continue }
      let classWeight: Double =
        switch definition.constraint {
        case .hard: 1.4
        case .core: 1
        case .soft: 0.45
        }
      let weight = definition.importance * classWeight
      weightedTotal += weight
      if state.policy == .skipped {
        skippedCount += 1
        continue
      }
      weightedQuality += weight * (state.score ?? 0)
    }

    guard weightedTotal > 0 else {
      conformance = .notApplicable
      return
    }
    let ratio = weightedQuality / weightedTotal
    switch ratio {
    case 0.94... where skippedCount == 0: conformance = .full
    case 0.76...: conformance = .high
    case 0.42...: conformance = .partial
    default: conformance = .low
    }
  }

  private func appendReplay(_ event: GuidanceReplayEvent) {
    guard isReplayRecordingEnabled else { return }
    replayEvents.append(event)
    if replayEvents.count > max(1, replayCapacity) {
      replayEvents.removeFirst(replayEvents.count - max(1, replayCapacity))
    }
  }

  private func appendTrace(
    _ category: SessionTraceCategory,
    frameID: Int? = nil,
    detail: String
  ) {
    traceSequence += 1
    trace.append(
      .init(sequence: traceSequence, frameID: frameID, category: category, detail: detail))
    if trace.count > max(1, traceCapacity) {
      trace.removeFirst(trace.count - max(1, traceCapacity))
    }
  }

  private func eventDescription(_ event: UserEvent) -> String {
    switch event {
    case .done: "done"
    case .anotherWay: "anotherWay"
    case .impossible: "impossible"
    case .cancel: "cancel"
    case .lock(let id): "lock:\(id.rawValue)"
    case .skip(let id): "skip:\(id.rawValue)"
    case .satisfied: "satisfied"
    case .resumeGuidance: "resumeGuidance"
    }
  }

  private func decisionDescription(_ decision: SchedulerDecision) -> String {
    switch decision {
    case .propose(let action): "propose:\(action.id.rawValue)"
    case .requestEvidence(let request):
      "requestEvidence:\(request.reason.rawValue):\(request.goals.map(\.rawValue).sorted().joined(separator: ","))"
    case .wait: "wait"
    case .ready: "ready"
    case .readyByUser: "readyByUser"
    case .paused: "paused"
    case .unreachable: "unreachable"
    case .unknown: "unknown"
    }
  }
}
