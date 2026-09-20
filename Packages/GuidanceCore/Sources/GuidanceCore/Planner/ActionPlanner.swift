import Foundation

public struct ControllerMemory: Sendable {
    public var declinePenalty: [ActionID: Int] = [:]
    public var oppositeEffects = 0
    public var fatigue = 0
    public var recentCancels = 0

    public init() {}
}

public enum UserEvent: Sendable {
    case done
    case anotherWay
    case impossible(ActionID)
    case cancel
    case lock(GoalID)
    case skip(GoalID)
    case satisfied
}

public enum PlannerOutcome: Equatable, Sendable {
    case none
    case verifyRequested
    case declined(ActionID)
    case constrained(String)
    case cancelled(ActionID)
    case goalLocked(GoalID)
    case goalSkipped(GoalID)
    case userSatisfied
}

public final class ActionPlanner {
    public var constraints = Set<SessionConstraint>()
    public var lockedGoals = Set<GoalID>()
    public var capabilities = Set<String>()
    public var memory = ControllerMemory()

    public private(set) var needsReobserve = false
    public private(set) var temporaryViolationWindowOpen = false
    public private(set) var lastTerminatedAction: ActionInstance?
    public private(set) var lastOutcome: PlannerOutcome = .none

    public init() {}

    public func feasible(_ action: ActionDefinition) -> Bool {
        action.safe
            && !constraints.contains(SessionConstraint(family: action.family))
            && (action.requiredCapability == nil
                || capabilities.contains(action.requiredCapability!))
            && action.damages.isDisjoint(with: lockedGoals)
    }

    public func utility(_ action: ActionDefinition) -> Double {
        action.expectedGain
            - action.risk
            - action.burden
            - action.uncertainty
            - Double(memory.declinePenalty[action.id] ?? 0) * 0.5
    }

    public func rank(_ actions: [ActionDefinition]) -> [ActionDefinition] {
        actions.filter(feasible).sorted { lhs, rhs in
            let left = utility(lhs)
            let right = utility(rhs)
            return left == right ? lhs.id.rawValue < rhs.id.rawValue : left > right
        }
    }

    public func openTemporaryViolationWindow() {
        temporaryViolationWindowOpen = true
    }

    public func clearReobserveRequest() {
        needsReobserve = false
    }

    public func apply(
        _ event: UserEvent,
        transaction: inout ActionInstance?,
        engine: GoalEngine? = nil
    ) {
        switch event {
        case .done:
            transaction?.state = .verifyRequested
            temporaryViolationWindowOpen = false
            needsReobserve = true
            lastOutcome = .verifyRequested

        case .anotherWay:
            if let actionID = transaction?.definition.id {
                memory.declinePenalty[actionID, default: 0] += 1
                transaction?.state = .declined
                lastOutcome = .declined(actionID)
            }
            memory.fatigue += 1

        case let .impossible(actionID):
            guard let definition = transaction?.definition, definition.id == actionID else {
                return
            }
            constraints.insert(SessionConstraint(family: definition.family))
            transaction?.state = .blocked
            lastOutcome = .constrained(definition.family)

        case .cancel:
            if var current = transaction {
                current.state = .cancelled
                lastTerminatedAction = current
                lastOutcome = .cancelled(current.definition.id)
            }
            transaction = nil
            temporaryViolationWindowOpen = false
            needsReobserve = true
            memory.recentCancels += 1

        case let .lock(goalID):
            lockedGoals.insert(goalID)
            engine?.setPolicy(.locked, for: goalID)
            lastOutcome = .goalLocked(goalID)

        case let .skip(goalID):
            engine?.setPolicy(.skipped, for: goalID)
            lastOutcome = .goalSkipped(goalID)

        case .satisfied:
            temporaryViolationWindowOpen = false
            lastOutcome = .userSatisfied
        }
    }
}
