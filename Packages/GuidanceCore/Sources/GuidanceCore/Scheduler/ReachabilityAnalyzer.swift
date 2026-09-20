import Foundation

public struct ReachabilityAssessment: Equatable, Sendable {
  public let reachableCriticalGoals: Set<GoalID>
  public let blockedCriticalGoals: Set<GoalID>
  public let unknownCriticalGoals: Set<GoalID>

  public init(
    reachableCriticalGoals: Set<GoalID> = [],
    blockedCriticalGoals: Set<GoalID> = [],
    unknownCriticalGoals: Set<GoalID> = []
  ) {
    self.reachableCriticalGoals = reachableCriticalGoals
    self.blockedCriticalGoals = blockedCriticalGoals
    self.unknownCriticalGoals = unknownCriticalGoals
  }

  public var hasBlockedCriticalGoal: Bool { !blockedCriticalGoals.isEmpty }
}

/// Runtime reachability under the *current* device, user constraints, safety
/// clearance and goal locks. This intentionally differs from static Recipe
/// validation: a valid recipe may become unreachable in one physical scene.
public struct ReachabilityAnalyzer: Sendable {
  public init() {}

  public func assess(
    engine: GoalEngine,
    planner: ActionPlanner,
    actions: [ActionDefinition]
  ) -> ReachabilityAssessment {
    var reachable = Set<GoalID>()
    var blocked = Set<GoalID>()
    var unknown = Set<GoalID>()

    for (id, runtime) in engine.states {
      guard runtime.policy != .skipped,
        let definition = engine.definitions[id],
        definition.constraint != .soft
      else { continue }

      switch runtime.state {
      case .satisfied:
        continue
      case .unknown, .unresolved, .inactive:
        unknown.insert(id)
      case .active, .drifted, .blocked:
        let candidates = actions.filter { $0.improvedGoals.contains(id) }
        if candidates.contains(where: { planner.feasible($0, engine: engine) }) {
          reachable.insert(id)
        } else {
          blocked.insert(id)
        }
      }
    }

    return ReachabilityAssessment(
      reachableCriticalGoals: reachable,
      blockedCriticalGoals: blocked,
      unknownCriticalGoals: unknown
    )
  }
}
