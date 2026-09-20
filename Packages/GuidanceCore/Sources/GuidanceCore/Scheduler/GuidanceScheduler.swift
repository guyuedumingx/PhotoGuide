import Foundation

public enum SchedulerDecision: Equatable, Sendable {
    case propose(ActionDefinition)
    case wait
    case ready
    case readyByUser
    case unreachable
    case unknown
}

public struct GuidanceScheduler: Sendable {
    public var marginalImprovementThreshold = 0.05
    public var oppositeEffectRecoveryThreshold = 2
    public var fatigueThreshold = 3

    public init() {}

    public func decide(
        engine: GoalEngine,
        planner: ActionPlanner,
        actions: [ActionDefinition],
        userSatisfied: Bool = false
    ) -> SchedulerDecision {
        if planner.needsReobserve { return .wait }
        if planner.memory.oppositeEffects >= oppositeEffectRecoveryThreshold { return .wait }
        if planner.memory.fatigue >= fatigueThreshold { return .wait }

        let relevant = engine.states.filter { $0.value.policy != .skipped }
        if relevant.isEmpty { return .ready }

        // "Looks good" stops normal optimization, but never suppresses a failed
        // safety/guard goal. A missing subject must still be surfaced.
        if userSatisfied {
            let blockingHardGoal = relevant.contains { entry in
                guard engine.definitions[entry.key]?.constraint == .hard else { return false }
                return entry.value.state != .satisfied
            }
            if !blockingHardGoal { return .readyByUser }
        }

        let focusGoals = Set(relevant.compactMap { entry in
            switch entry.value.state {
            case .active, .drifted:
                return entry.key
            default:
                return nil
            }
        })
        let unknownHardGuard = relevant.contains { entry in
            guard engine.definitions[entry.key]?.constraint == .hard else { return false }
            return entry.value.state == .unknown || entry.value.state == .unresolved
        }
        if unknownHardGuard { return .unknown }
        if relevant.contains(where: { $0.value.state == .blocked }) { return .unreachable }
        if relevant.allSatisfy({ $0.value.state == .satisfied }) { return .ready }
        if focusGoals.isEmpty,
           relevant.contains(where: { $0.value.state == .unknown || $0.value.state == .unresolved }) {
            return .unknown
        }

        let candidates = actions.filter { !$0.affects.isDisjoint(with: focusGoals) }
        let ranked = planner.rank(candidates)

        guard let first = ranked.first else { return .unreachable }
        if planner.utility(first) < marginalImprovementThreshold {
            let hasUnsatisfiedHardGoal = focusGoals.contains { goalID in
                engine.definitions[goalID]?.constraint == .hard
            }
            return hasUnsatisfiedHardGoal ? .unreachable : .ready
        }

        return .propose(first)
    }
}
