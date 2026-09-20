import Foundation

/// Deterministic input log for reproducing a controller session. The log stores
/// only external inputs and explicit decision ticks; derived state is rebuilt by
/// GuidanceCore during replay.
public enum GuidanceReplayEvent: Codable, Equatable, Sendable {
  /// Advances the controller's processed-frame clock even when no evaluator
  /// produced a usable observation for that frame.
  case frame(Int)
  case observation(Observation)
  case batch([Observation])
  case sceneConditions(SceneConditionProfile?)
  case capabilities(Set<String>)
  case safetyClearance(family: String, granted: Bool)
  case resetUserOverrides
  case restore(GuidanceSessionCheckpoint)
  case runtimePause(RuntimePauseReason)
  case runtimeResume
  case user(UserEvent)
  case tick
}

public struct GuidanceReplayResult: Equatable, Sendable {
  public let snapshot: GuidanceSnapshot
  public let decisions: [ReplayDecision]
  public let invariantIssues: [RuntimeInvariantIssue]

  public init(
    snapshot: GuidanceSnapshot,
    decisions: [ReplayDecision],
    invariantIssues: [RuntimeInvariantIssue]
  ) {
    self.snapshot = snapshot
    self.decisions = decisions
    self.invariantIssues = invariantIssues
  }
}

public enum ReplayDecision: Codable, Equatable, Sendable {
  case propose(ActionID)
  case requestEvidence(EvidenceReason, [GoalID])
  case wait
  case ready
  case readyByUser
  case paused
  case unreachable
  case unknown

  init(_ decision: SchedulerDecision) {
    switch decision {
    case .propose(let action): self = .propose(action.id)
    case .requestEvidence(let request):
      self = .requestEvidence(request.reason, request.goals.sorted { $0.rawValue < $1.rawValue })
    case .wait: self = .wait
    case .ready: self = .ready
    case .readyByUser: self = .readyByUser
    case .paused: self = .paused
    case .unreachable: self = .unreachable
    case .unknown: self = .unknown
    }
  }
}

public struct GuidanceReplayer: Sendable {
  public init() {}

  public func replay(
    _ events: [GuidanceReplayEvent],
    goals: [GoalDefinition],
    actions: [ActionDefinition],
    goalGroups: [GoalGroupDefinition] = [],
    registry: GuidanceRegistry? = nil,
    configure: ((GuidanceSession) -> Void)? = nil
  ) -> GuidanceReplayResult {
    let session = GuidanceSession(
      goals: goals, actions: actions, goalGroups: goalGroups, registry: registry)
    session.isReplayRecordingEnabled = false
    configure?(session)
    var decisions = [ReplayDecision]()

    for event in events {
      switch event {
      case .frame(let frameID):
        session.advanceFrame(frameID)
      case .observation(let observation):
        session.ingest(observation)
      case .batch(let observations):
        session.ingestBatch(observations)
      case .sceneConditions(let profile):
        session.updateSceneConditions(profile)
      case .capabilities(let capabilities):
        session.updateCapabilities(capabilities)
      case .safetyClearance(let family, let granted):
        if granted {
          session.grantSafetyClearance(for: family)
        } else {
          session.revokeSafetyClearance(for: family)
        }
      case .resetUserOverrides:
        session.resetUserOverrides()
      case .restore(let checkpoint):
        _ = session.restore(from: checkpoint)
      case .runtimePause(let reason):
        session.pauseRuntime(reason)
      case .runtimeResume:
        session.resumeRuntime()
      case .user(let event):
        session.handle(event)
      case .tick:
        decisions.append(ReplayDecision(session.tick()))
      }
    }

    return GuidanceReplayResult(
      snapshot: session.snapshot(),
      decisions: decisions,
      invariantIssues: session.invariantIssues()
    )
  }
}
