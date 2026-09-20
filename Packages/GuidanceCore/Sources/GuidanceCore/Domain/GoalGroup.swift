import Foundation

/// Goal groups are a composition layer above the six kernel primitives. They
/// let a recipe express a joint target or an explicit trade-off without
/// introducing a new primitive or pretending each member can be optimized
/// independently.
public enum GoalGroupKind: String, Codable, Sendable {
  case joint
  case tradeoff
}

public struct GoalGroupMember: Codable, Equatable, Sendable {
  public let goal: GoalID
  public let weight: Double

  public init(goal: GoalID, weight: Double = 1) {
    self.goal = goal
    self.weight = weight.isFinite ? max(0, weight) : 0
  }
}

public struct GoalGroupDefinition: Codable, Equatable, Sendable {
  public let id: GoalGroupID
  public let kind: GoalGroupKind
  public let members: [GoalGroupMember]
  /// A group is not ready when any known member falls below this floor.
  public let minimumMemberScore: Double
  /// Group-level utility target used by ReadinessPolicy.
  public let targetScore: Double
  /// Trade-off groups penalize a wide spread between their strongest and
  /// weakest member. Joint groups ignore this value.
  public let balanceTolerance: Double
  public let importance: Double

  public init(
    id: GoalGroupID,
    kind: GoalGroupKind,
    members: [GoalGroupMember],
    minimumMemberScore: Double = 0.55,
    targetScore: Double = 0.72,
    balanceTolerance: Double = 0.30,
    importance: Double = 1
  ) {
    self.id = id
    self.kind = kind
    self.members = members
    self.minimumMemberScore = Self.clamp(minimumMemberScore)
    self.targetScore = Self.clamp(targetScore)
    self.balanceTolerance = Self.clamp(balanceTolerance)
    self.importance = Self.clamp(importance)
  }

  private static func clamp(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
  }
}

public struct GoalGroupAssessment: Equatable, Sendable {
  public let id: GoalGroupID
  public let known: Bool
  public let score: Double?
  public let minimumMemberScore: Double?
  public let spread: Double?
  public let satisfied: Bool

  public init(
    id: GoalGroupID,
    known: Bool,
    score: Double?,
    minimumMemberScore: Double?,
    spread: Double?,
    satisfied: Bool
  ) {
    self.id = id
    self.known = known
    self.score = score
    self.minimumMemberScore = minimumMemberScore
    self.spread = spread
    self.satisfied = satisfied
  }
}
