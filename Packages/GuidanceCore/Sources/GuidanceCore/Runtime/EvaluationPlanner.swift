import Foundation

public enum EvaluationCadence: String, Codable, Sendable {
  case guardFast
  case focus
  case watch
}

public struct EvaluationSlot: Hashable, Codable, Sendable {
  public let goalID: GoalID
  public let dimension: DimensionID
  public let binding: Binding
  public let cadence: EvaluationCadence

  public init(
    goalID: GoalID, dimension: DimensionID, binding: Binding, cadence: EvaluationCadence
  ) {
    self.goalID = goalID
    self.dimension = dimension
    self.binding = binding
    self.cadence = cadence
  }
}

public struct EvaluationPlan: Sendable {
  public let local: [EvaluationSlot]
  public let semantic: [EvaluationSlot]

  public init(local: [EvaluationSlot], semantic: [EvaluationSlot]) {
    self.local = local
    self.semantic = semantic
  }
}

/// Decides *what* should be observed, independently from the camera and model.
/// Semantic slots are intentionally batched so one current image can answer many dimensions.
public struct EvaluationPlanner: Sendable {
  public var semanticConfidenceThreshold = 0.74

  public init() {}

  public func plan(
    engine: GoalEngine,
    registry: GuidanceRegistry,
    availableEvaluators: Set<EvaluatorID>? = nil
  ) -> EvaluationPlan {
    var local = Set<EvaluationSlot>()
    var semantic = Set<EvaluationSlot>()

    for (goalID, runtime) in engine.states where runtime.policy != .skipped {
      guard let goal = engine.definitions[goalID],
        let dimension = registry.dimensions[goal.dimension]
      else { continue }
      let cadence: EvaluationCadence
      if goal.constraint == .hard {
        cadence = .guardFast
      } else if runtime.state == .active || runtime.state == .drifted || runtime.state == .unknown
        || runtime.dirty
      {
        cadence = .focus
      } else {
        cadence = .watch
      }

      let slot = EvaluationSlot(
        goalID: goalID, dimension: goal.dimension, binding: goal.binding, cadence: cadence)
      let evaluatorIDs = dimension.evaluatorIDs.filter { availableEvaluators?.contains($0) ?? true }
      let evaluators = evaluatorIDs.compactMap { registry.evaluators[$0] }
      let localAvailable = evaluators.contains {
        $0.kind == .localVision || $0.kind == .localTelemetry || $0.kind == .temporal
      }
      let semanticAvailable = evaluators.contains { $0.kind == .semanticRemote }

      if localAvailable { local.insert(slot) }
      let confidence = runtime.confidence ?? 0
      let semanticNeeded =
        semanticAvailable
        && (!localAvailable
          || runtime.state == .active
          || runtime.state == .drifted
          || runtime.state == .unknown
          || confidence < semanticConfidenceThreshold)
      if semanticNeeded { semantic.insert(slot) }
    }

    return EvaluationPlan(
      local: local.sorted(by: Self.sortSlots),
      semantic: semantic.sorted(by: Self.sortSlots)
    )
  }

  private static func sortSlots(_ lhs: EvaluationSlot, _ rhs: EvaluationSlot) -> Bool {
    if lhs.cadence != rhs.cadence {
      let rank: [EvaluationCadence: Int] = [.guardFast: 0, .focus: 1, .watch: 2]
      return rank[lhs.cadence, default: 3] < rank[rhs.cadence, default: 3]
    }
    if lhs.dimension != rhs.dimension {
      return lhs.dimension.rawValue < rhs.dimension.rawValue
    }
    return lhs.goalID.rawValue < rhs.goalID.rawValue
  }
}
