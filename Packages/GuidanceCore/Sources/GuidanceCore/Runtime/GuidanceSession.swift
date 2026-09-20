import Foundation

public enum CaptureState: String, Codable, Sendable {
    case unknown
    case notReady
    case improvable
    case ready
    case readyByUser
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

public final class GuidanceSession {
    public let engine: GoalEngine
    public let planner: ActionPlanner
    public var scheduler: GuidanceScheduler
    public let actions: [ActionDefinition]

    public private(set) var captureState: CaptureState = .unknown
    public private(set) var conformance: Conformance = .low
    public private(set) var userSatisfied = false
    public private(set) var lastObservedFrame = 0
    public private(set) var verificationRequestedAfterFrame: Int?

    public init(goals: [GoalDefinition], actions: [ActionDefinition]) {
        engine = GoalEngine(goals)
        planner = ActionPlanner()
        scheduler = GuidanceScheduler()
        self.actions = actions
        refreshConformance()
    }

    @discardableResult
    public func ingest(_ observation: Observation) -> [GoalID] {
        let updated = engine.ingestAll(observation)
        lastObservedFrame = max(lastObservedFrame, observation.frameID)
        if !updated.isEmpty,
           let verificationRequestedAfterFrame,
           observation.frameID > verificationRequestedAfterFrame {
            self.verificationRequestedAfterFrame = nil
            planner.clearReobserveRequest()
        }
        refreshConformance()
        return updated
    }

    public func handle(_ event: UserEvent, transaction: inout ActionInstance?) {
        planner.apply(event, transaction: &transaction, engine: engine)
        switch event {
        case .done, .cancel:
            verificationRequestedAfterFrame = lastObservedFrame
        case .satisfied:
            userSatisfied = true
            captureState = .readyByUser
        default:
            break
        }
        refreshConformance()
    }

    public func resetUserOverrides() {
        userSatisfied = false
        verificationRequestedAfterFrame = nil
        planner.clearReobserveRequest()
    }

    @discardableResult
    public func tick() -> SchedulerDecision {
        let decision = scheduler.decide(
            engine: engine,
            planner: planner,
            actions: actions,
            userSatisfied: userSatisfied
        )

        switch decision {
        case .ready:
            captureState = .ready
        case .readyByUser:
            captureState = .readyByUser
        case .unknown:
            captureState = .unknown
        case .unreachable:
            captureState = .unreachable
        case .propose:
            captureState = .improvable
        case .wait:
            captureState = .notReady
        }

        refreshConformance()
        return decision
    }

    public func readiness() -> Readiness {
        Readiness(state: captureState, conformance: conformance)
    }

    private func refreshConformance() {
        let states = Array(engine.states.values)
        guard !states.isEmpty else {
            conformance = .notApplicable
            return
        }

        let satisfied = states.filter { $0.state == .satisfied }.count
        let skipped = states.filter { $0.policy == .skipped }.count
        let ratio = Double(satisfied) / Double(states.count)

        if skipped == states.count {
            conformance = .partial
            return
        }

        switch ratio {
        case 1 where skipped == 0:
            conformance = .full
        case 0.8...:
            conformance = .high
        case 0.4...:
            conformance = .partial
        default:
            conformance = .low
        }
    }
}
