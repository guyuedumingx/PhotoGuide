import Foundation

public enum EvidenceReason: String, Codable, Sendable {
  case hardGuardUnknown
  case coreUnknown
  case lowConfidence
  case staleOrMissing
}

/// Explicit information need produced by the scheduler. This prevents UNKNOWN
/// from being treated as a bad photograph and lets the UI/runtime choose the
/// cheapest information action (hold, wait, reveal subject, select anchor).
public struct EvidenceRequest: Codable, Equatable, Sendable {
  public let goals: Set<GoalID>
  public let reason: EvidenceReason
  public let preferredOperation: ActionOperation

  public init(
    goals: Set<GoalID>,
    reason: EvidenceReason,
    preferredOperation: ActionOperation = .hold
  ) {
    self.goals = goals
    self.reason = reason
    self.preferredOperation = preferredOperation
  }
}
