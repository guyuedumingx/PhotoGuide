import Foundation

/// Registry structure that affects observation validation, evaluator routing
/// and learned reliability. It is part of a v2 checkpoint definition signature.
public struct SessionRegistrySignature: Codable, Equatable, Sendable {
  public let nodes: [NodeDefinition]
  public let relations: [RelationDefinition]
  public let dimensions: [DimensionDefinition]
  public let evaluators: [EvaluatorDefinition]

  public init(_ registry: GuidanceRegistry) {
    nodes = registry.nodes.values.sorted { $0.id.rawValue < $1.id.rawValue }
    relations = registry.relations.values.sorted { $0.id.rawValue < $1.id.rawValue }
    dimensions = registry.dimensions.values.sorted { $0.id.rawValue < $1.id.rawValue }
    evaluators = registry.evaluators.values.sorted { $0.id.rawValue < $1.id.rawValue }
  }
}

/// Full structural signature, not just IDs. A checkpoint created against one
/// recipe revision must never be applied to another revision that silently
/// changed targets, action effects, safety semantics, dependencies or runtime
/// evaluator contracts.
public struct SessionDefinitionSignature: Codable, Equatable, Sendable {
  public let goals: [GoalDefinition]
  public let actions: [ActionDefinition]
  public let goalGroups: [GoalGroupDefinition]
  /// Optional so v0.3.8/schema-v1 checkpoints remain decodable.
  public let registry: SessionRegistrySignature?

  public init(
    goals: [GoalDefinition],
    actions: [ActionDefinition],
    goalGroups: [GoalGroupDefinition],
    registry: GuidanceRegistry? = nil
  ) {
    self.goals = goals.sorted { $0.id.rawValue < $1.id.rawValue }
    self.actions = actions.sorted { $0.id.rawValue < $1.id.rawValue }
    self.goalGroups = goalGroups.sorted { $0.id.rawValue < $1.id.rawValue }
    self.registry = registry.map(SessionRegistrySignature.init)
  }

  public func matchesLegacyStructure(_ other: SessionDefinitionSignature) -> Bool {
    goals == other.goals && actions == other.actions && goalGroups == other.goalGroups
  }
}

public struct PlannerCheckpoint: Codable, Equatable, Sendable {
  public let constraints: Set<SessionConstraint>
  public let lockedGoals: Set<GoalID>
  public let memory: ControllerMemory

  public init(
    constraints: Set<SessionConstraint>,
    lockedGoals: Set<GoalID>,
    memory: ControllerMemory
  ) {
    self.constraints = constraints
    self.lockedGoals = lockedGoals
    self.memory = memory
  }
}

public struct GuidanceSessionCheckpoint: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let signature: SessionDefinitionSignature
  public let goalPolicies: [GoalID: UserGoalPolicy]
  public let planner: PlannerCheckpoint
  public let evaluatorReliability: EvaluatorReliabilityModel
  public let sourceFrameID: Int

  public init(
    schemaVersion: Int = 2,
    signature: SessionDefinitionSignature,
    goalPolicies: [GoalID: UserGoalPolicy],
    planner: PlannerCheckpoint,
    evaluatorReliability: EvaluatorReliabilityModel,
    sourceFrameID: Int
  ) {
    self.schemaVersion = schemaVersion
    self.signature = signature
    self.goalPolicies = goalPolicies
    self.planner = planner
    self.evaluatorReliability = evaluatorReliability
    self.sourceFrameID = sourceFrameID
  }
}

public enum CheckpointRestoreResult: Equatable, Sendable {
  case restored
  case rejectedSchema
  case rejectedDefinitionMismatch
}

public enum RuntimePauseReason: String, Codable, Sendable {
  case appBackgrounded
  case cameraInterrupted
  case inputPipelineInterrupted
  case hostRequested
}
