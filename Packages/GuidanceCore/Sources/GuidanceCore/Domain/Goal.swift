import Foundation

public enum ConstraintClass: Int, Codable, Comparable, Sendable {
    case soft
    case core
    case hard

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum GoalState: String, Codable, Sendable {
    case inactive
    case unresolved
    case active
    case satisfied
    case drifted
    case unknown
    case blocked
}

public enum UserGoalPolicy: String, Codable, Sendable {
    case normal
    case locked
    case deprioritized
    case skipped
}

public struct TargetBand: Codable, Equatable, Sendable {
    public let ideal: ClosedRange<Double>
    public let acceptable: ClosedRange<Double>

    public init(ideal: ClosedRange<Double>, acceptable: ClosedRange<Double>) {
        self.ideal = ideal
        self.acceptable = acceptable
    }
}

public enum GoalTarget: Codable, Equatable, Sendable {
    case band(TargetBand)
    case ordinal(Int)
    case boolean(Bool)
    case categorical(String)
}

public struct StabilityPolicy: Codable, Equatable, Sendable {
    public let enterThreshold: Double
    public let exitThreshold: Double
    public let enterFrames: Int
    public let exitFrames: Int

    public init(
        enterThreshold: Double = 0.95,
        exitThreshold: Double = 0.75,
        enterFrames: Int = 2,
        exitFrames: Int = 2
    ) {
        self.enterThreshold = enterThreshold
        self.exitThreshold = exitThreshold
        self.enterFrames = max(1, enterFrames)
        self.exitFrames = max(1, exitFrames)
    }
}

public struct GoalDefinition: Codable, Equatable, Sendable {
    public let id: GoalID
    public let dimension: DimensionID
    public let binding: Binding
    public let target: GoalTarget
    public let constraint: ConstraintClass
    public let importance: Double
    public let dependencies: Set<GoalID>
    public let stability: StabilityPolicy

    public init(
        id: GoalID,
        dimension: DimensionID,
        binding: Binding,
        target: GoalTarget,
        constraint: ConstraintClass,
        importance: Double = 1,
        dependencies: Set<GoalID> = [],
        stability: StabilityPolicy = StabilityPolicy()
    ) {
        self.id = id
        self.dimension = dimension
        self.binding = binding
        self.target = target
        self.constraint = constraint
        self.importance = min(max(importance, 0), 1)
        self.dependencies = dependencies
        self.stability = stability
    }
}

public struct GoalRuntimeState: Codable, Equatable, Sendable {
    public var state: GoalState = .unresolved
    public var policy: UserGoalPolicy = .normal
    public var score: Double?
    public var confidence: Double?
    public var enterCounter = 0
    public var exitCounter = 0
    public var dirty = true
    public var lastUpdatedFrame: Int?

    public init() {}
}
