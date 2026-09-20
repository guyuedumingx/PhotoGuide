import Foundation

public enum ConstraintClass: Int, Codable, Comparable, Sendable {
  case soft = 0
  case core = 1
  case hard = 2

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
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

  public var isWellFormed: Bool {
    acceptable.lowerBound <= ideal.lowerBound
      && ideal.lowerBound <= ideal.upperBound
      && ideal.upperBound <= acceptable.upperBound
      && ideal.lowerBound.isFinite
      && ideal.upperBound.isFinite
      && acceptable.lowerBound.isFinite
      && acceptable.upperBound.isFinite
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
    enterThreshold: Double = 0.82,
    exitThreshold: Double = 0.68,
    enterFrames: Int = 2,
    exitFrames: Int = 2
  ) {
    self.enterThreshold = min(max(enterThreshold, 0), 1)
    self.exitThreshold = min(max(exitThreshold, 0), self.enterThreshold)
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
  public let skippable: Bool
  public let minimumConfidence: Double

  public init(
    id: GoalID,
    dimension: DimensionID,
    binding: Binding,
    target: GoalTarget,
    constraint: ConstraintClass,
    importance: Double = 1,
    dependencies: Set<GoalID> = [],
    stability: StabilityPolicy = StabilityPolicy(),
    skippable: Bool? = nil,
    minimumConfidence: Double = 0.5
  ) {
    self.id = id
    self.dimension = dimension
    self.binding = binding
    self.target = target
    self.constraint = constraint
    self.importance = min(max(importance, 0), 1)
    self.dependencies = dependencies
    self.stability = stability
    self.skippable = skippable ?? (constraint != .hard)
    self.minimumConfidence = min(max(minimumConfidence, 0), 1)
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
  /// The last frame that changed a hysteresis counter. Multiple evaluators may
  /// report the same frame; they must not count as multiple stable frames.
  public var lastHysteresisFrame: Int?
  public var lastBindingVersion = 0
  public var lastSceneRevision = 0

  public init() {}
}
