import Foundation

public struct GoalGroupEvaluator: Sendable {
  public var jointGeneralizedMeanPower = -4.0
  public var tradeoffSpreadPenalty = 0.45

  public init() {}

  public func assess(_ group: GoalGroupDefinition, engine: GoalEngine) -> GoalGroupAssessment {
    let activeMembers = group.members.filter { member in
      engine.states[member.goal]?.policy != .skipped
    }
    guard !activeMembers.isEmpty else {
      return .init(
        id: group.id, known: true, score: 1, minimumMemberScore: 1, spread: 0, satisfied: true)
    }

    var values = [(score: Double, weight: Double)]()
    for member in activeMembers {
      guard let state = engine.states[member.goal], let score = state.score,
        state.state != .unknown, state.state != .unresolved, state.state != .inactive
      else {
        return .init(
          id: group.id, known: false, score: nil, minimumMemberScore: nil, spread: nil,
          satisfied: false)
      }
      let policyWeight = state.policy == .deprioritized ? 0.35 : 1.0
      values.append((min(max(score, 0), 1), max(0.0001, member.weight * policyWeight)))
    }

    let minScore = values.map(\.score).min() ?? 0
    let maxScore = values.map(\.score).max() ?? 0
    let spread = maxScore - minScore
    let score: Double
    switch group.kind {
    case .joint:
      score = generalizedMean(values, power: jointGeneralizedMeanPower)
    case .tradeoff:
      let weightedMean = weightedArithmeticMean(values)
      let excessSpread = max(0, spread - group.balanceTolerance)
      score = max(0, weightedMean - excessSpread * tradeoffSpreadPenalty)
    }

    let clamped = min(max(score, 0), 1)
    return .init(
      id: group.id,
      known: true,
      score: clamped,
      minimumMemberScore: minScore,
      spread: spread,
      satisfied: minScore >= group.minimumMemberScore && clamped >= group.targetScore
    )
  }

  /// Scheduler multiplier for one member of a joint/trade-off surface. The
  /// weakest member is intentionally favored; an already-strong member in an
  /// imbalanced trade-off is damped so the controller does not ping-pong.
  public func priorityMultiplier(
    for goalID: GoalID,
    groups: [GoalGroupDefinition],
    engine: GoalEngine
  ) -> Double {
    var multiplier = 1.0
    for group in groups where group.members.contains(where: { $0.goal == goalID }) {
      let memberScores = group.members.compactMap { member -> (GoalID, Double)? in
        guard engine.states[member.goal]?.policy != .skipped,
          let score = engine.states[member.goal]?.score
        else { return nil }
        return (member.goal, score)
      }
      guard memberScores.count >= 2,
        let current = memberScores.first(where: { $0.0 == goalID })?.1,
        let weakest = memberScores.map(\.1).min(),
        let strongest = memberScores.map(\.1).max()
      else { continue }

      let spread = strongest - weakest
      switch group.kind {
      case .joint:
        if abs(current - weakest) < 0.0001 {
          multiplier *= 1.35
        } else if spread > 0.25 {
          multiplier *= 0.85
        }
      case .tradeoff:
        if abs(current - weakest) < 0.0001 {
          multiplier *= 1.55
        } else if spread > group.balanceTolerance {
          multiplier *= 0.45
        }
      }
    }
    return multiplier
  }

  private func generalizedMean(_ values: [(score: Double, weight: Double)], power: Double) -> Double
  {
    let totalWeight = values.reduce(0) { $0 + $1.weight }
    guard totalWeight > 0 else { return 0 }
    if abs(power) < 0.0001 {
      let logMean =
        values.reduce(0.0) { total, item in
          total + item.weight * log(max(item.score, 0.0001))
        } / totalWeight
      return exp(logMean)
    }
    let sum =
      values.reduce(0.0) { total, item in
        total + item.weight * pow(max(item.score, 0.0001), power)
      } / totalWeight
    return pow(max(sum, 0.0000001), 1 / power)
  }

  private func weightedArithmeticMean(_ values: [(score: Double, weight: Double)]) -> Double {
    let totalWeight = values.reduce(0) { $0 + $1.weight }
    guard totalWeight > 0 else { return 0 }
    return values.reduce(0.0) { $0 + $1.score * $1.weight } / totalWeight
  }
}
