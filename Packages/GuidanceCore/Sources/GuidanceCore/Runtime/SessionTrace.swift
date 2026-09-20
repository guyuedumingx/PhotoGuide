import Foundation

public enum SessionTraceCategory: String, Codable, Sendable {
  case observation
  case validation
  case userEvent
  case decision
  case verification
  case constraint
  case lifecycle
  case fault
  case checkpoint
}

public struct SessionTraceEvent: Codable, Equatable, Sendable {
  public let sequence: Int
  public let frameID: Int?
  public let category: SessionTraceCategory
  public let detail: String

  public init(sequence: Int, frameID: Int?, category: SessionTraceCategory, detail: String) {
    self.sequence = sequence
    self.frameID = frameID
    self.category = category
    self.detail = detail
  }
}

public struct ControllerMemorySnapshot: Codable, Equatable, Sendable {
  public let fatigue: Int
  public let recentCancels: Int
  public let oppositeEffects: Int
  public let successfulActions: Int
}

public struct EvaluatorReliabilitySnapshot: Codable, Equatable, Sendable {
  public let evaluator: EvaluatorID
  public let dimension: DimensionID
  public let reliability: Double
  public let sampleCount: Int
  public let conflictCount: Int

  public init(
    evaluator: EvaluatorID, dimension: DimensionID, reliability: Double,
    sampleCount: Int, conflictCount: Int
  ) {
    self.evaluator = evaluator
    self.dimension = dimension
    self.reliability = reliability
    self.sampleCount = sampleCount
    self.conflictCount = conflictCount
  }
}

public struct GoalConflictSnapshot: Codable, Equatable, Sendable {
  public let goal: GoalID
  public let report: ObservationConflictReport

  public init(goal: GoalID, report: ObservationConflictReport) {
    self.goal = goal
    self.report = report
  }
}

public struct GuidanceSnapshot: Codable, Equatable, Sendable {
  public let captureState: CaptureState
  public let conformance: Conformance
  public let currentActionID: ActionID?
  public let currentActionState: ActionState?
  public let activePlanID: ActionPlanID?
  public let activePlanState: ActionPlanState?
  public let activePlanStepIndex: Int?
  public let verificationPending: Bool
  public let userSatisfied: Bool
  public let capabilities: Set<String>
  public let constraints: Set<SessionConstraint>
  public let safetyClearances: Set<String>
  public let tickSequence: Int
  public let goalStates: [GoalID: GoalRuntimeState]
  public let memory: ControllerMemorySnapshot
  /// Monotonic processed-frame clock used by controller timeouts. The name is
  /// retained for source compatibility with earlier v0.3 builds.
  public let lastObservedFrame: Int
  public let rejectedObservations: Int
  public let evaluatorReliability: [EvaluatorReliabilitySnapshot]
  public let conflicts: [GoalConflictSnapshot]
  public let sceneConditions: SceneConditionProfile?
  public let runtimePauseReason: RuntimePauseReason?

  public init(
    captureState: CaptureState,
    conformance: Conformance,
    currentActionID: ActionID?,
    currentActionState: ActionState? = nil,
    activePlanID: ActionPlanID? = nil,
    activePlanState: ActionPlanState? = nil,
    activePlanStepIndex: Int? = nil,
    verificationPending: Bool = false,
    userSatisfied: Bool = false,
    capabilities: Set<String> = [],
    constraints: Set<SessionConstraint> = [],
    safetyClearances: Set<String> = [],
    tickSequence: Int = 0,
    goalStates: [GoalID: GoalRuntimeState],
    memory: ControllerMemorySnapshot,
    lastObservedFrame: Int,
    rejectedObservations: Int = 0,
    evaluatorReliability: [EvaluatorReliabilitySnapshot] = [],
    conflicts: [GoalConflictSnapshot] = [],
    sceneConditions: SceneConditionProfile? = nil,
    runtimePauseReason: RuntimePauseReason? = nil
  ) {
    self.captureState = captureState
    self.conformance = conformance
    self.currentActionID = currentActionID
    self.currentActionState = currentActionState
    self.activePlanID = activePlanID
    self.activePlanState = activePlanState
    self.activePlanStepIndex = activePlanStepIndex
    self.verificationPending = verificationPending
    self.userSatisfied = userSatisfied
    self.capabilities = capabilities
    self.constraints = constraints
    self.safetyClearances = safetyClearances
    self.tickSequence = tickSequence
    self.goalStates = goalStates
    self.memory = memory
    self.lastObservedFrame = lastObservedFrame
    self.rejectedObservations = rejectedObservations
    self.evaluatorReliability = evaluatorReliability
    self.conflicts = conflicts
    self.sceneConditions = sceneConditions
    self.runtimePauseReason = runtimePauseReason
  }
}
