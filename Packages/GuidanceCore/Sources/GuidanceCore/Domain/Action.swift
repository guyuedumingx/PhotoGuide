import Foundation

public struct ActionDefinition: Codable, Equatable, Sendable {
    public let id: ActionID
    public let affects: Set<GoalID>
    public let damages: Set<GoalID>
    public let expectedGain: Double
    public let burden: Double
    public let risk: Double
    public let uncertainty: Double
    public let family: String
    public let requiredCapability: String?
    public let safe: Bool

    public init(
        id: ActionID,
        affects: Set<GoalID>,
        damages: Set<GoalID> = [],
        expectedGain: Double,
        burden: Double = 0,
        risk: Double = 0,
        uncertainty: Double = 0,
        family: String = "default",
        requiredCapability: String? = nil,
        safe: Bool = true
    ) {
        self.id = id
        self.affects = affects
        self.damages = damages
        self.expectedGain = expectedGain
        self.burden = burden
        self.risk = risk
        self.uncertainty = uncertainty
        self.family = family
        self.requiredCapability = requiredCapability
        self.safe = safe
    }
}

public enum ActionState: String, Codable, Sendable {
    case proposed
    case accepted
    case executing
    case partial
    case verifyRequested
    case completed
    case declined
    case cancelled
    case failed
    case blocked
    case skipped
}

public struct ActionInstance: Codable, Equatable, Sendable {
    public let definition: ActionDefinition
    public var state: ActionState = .proposed

    public init(_ definition: ActionDefinition) {
        self.definition = definition
    }
}

public struct SessionConstraint: Codable, Hashable, Sendable {
    public let family: String
    public init(family: String) { self.family = family }
}
