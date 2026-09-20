import Foundation

/// Concurrency-safe façade for clients that do not want to pin the controller
/// to MainActor. The mutable GuidanceSession never crosses the actor boundary.
public actor GuidanceRuntimeActor {
  private let session: GuidanceSession

  public init(
    goals: [GoalDefinition],
    actions: [ActionDefinition],
    goalGroups: [GoalGroupDefinition] = [],
    registry: GuidanceRegistry? = nil
  ) {
    session = GuidanceSession(
      goals: goals, actions: actions, goalGroups: goalGroups, registry: registry)
  }

  @discardableResult
  public func ingest(_ observation: Observation) -> [GoalID] {
    session.ingest(observation)
  }

  @discardableResult
  public func ingestBatch(_ observations: [Observation]) -> [GoalID] {
    session.ingestBatch(observations)
  }

  public func advanceFrame(_ frameID: Int) { session.advanceFrame(frameID) }

  public func handle(_ event: UserEvent) { session.handle(event) }

  public func updateCapabilities(_ capabilities: Set<String>) {
    session.updateCapabilities(capabilities)
  }

  public func updateSceneConditions(_ profile: SceneConditionProfile?) {
    session.updateSceneConditions(profile)
  }

  public func pauseRuntime(_ reason: RuntimePauseReason) { session.pauseRuntime(reason) }

  public func resumeRuntime() { session.resumeRuntime() }

  public func checkpoint() -> GuidanceSessionCheckpoint { session.checkpoint() }

  @discardableResult
  public func restore(from checkpoint: GuidanceSessionCheckpoint) -> CheckpointRestoreResult {
    session.restore(from: checkpoint)
  }

  @discardableResult
  public func tick() -> SchedulerDecision { session.tick() }

  public func tickDetailed() -> RuntimeTickReport { session.tickDetailed() }

  public func replayEvents() -> [GuidanceReplayEvent] { session.replayEvents }

  public func snapshot() -> GuidanceSnapshot { session.snapshot() }

  public func readiness() -> Readiness { session.readiness() }

  public func invariantIssues() -> [RuntimeInvariantIssue] { session.invariantIssues() }

  public func grantSafetyClearance(for actionFamily: String) {
    session.grantSafetyClearance(for: actionFamily)
  }

  public func revokeSafetyClearance(for actionFamily: String) {
    session.revokeSafetyClearance(for: actionFamily)
  }

  public func resetUserOverrides() { session.resetUserOverrides() }
}
