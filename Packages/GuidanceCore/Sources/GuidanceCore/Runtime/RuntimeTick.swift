import Foundation

/// Stable controller phase names. Keeping this sequence explicit is useful for
/// trace analysis and prevents future refactors from silently reordering the
/// safety-critical control path.
public enum RuntimeTickPhase: String, Codable, CaseIterable, Sendable {
  case updateBindings
  case ingestObservations
  case stabilizeObservations
  case updateGoalStates
  case propagateInvalidations
  case detectRegression
  case updateControllerMemory
  case evaluateReachability
  case selectFocusGoals
  case generateCandidateActions
  case applyHardFilters
  case rankFeasibleActions
  case detectOscillationAndFatigue
  case mergeAndDecide
}

public struct RuntimeTickReport: Equatable, Sendable {
  public let sequence: Int
  public let phases: [RuntimeTickPhase]
  public let workSets: GoalWorkSets
  public let decision: ReplayDecision
  public let readiness: Readiness
  public let invariantIssues: [RuntimeInvariantIssue]

  public init(
    sequence: Int,
    phases: [RuntimeTickPhase],
    workSets: GoalWorkSets,
    decision: ReplayDecision,
    readiness: Readiness,
    invariantIssues: [RuntimeInvariantIssue]
  ) {
    self.sequence = sequence
    self.phases = phases
    self.workSets = workSets
    self.decision = decision
    self.readiness = readiness
    self.invariantIssues = invariantIssues
  }
}
