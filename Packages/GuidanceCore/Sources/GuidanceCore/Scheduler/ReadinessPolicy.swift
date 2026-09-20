import Foundation

public struct ReadinessAssessment: Equatable, Sendable {
  public let hardSatisfied: Bool
  public let allCoreKnown: Bool
  public let minimumCoreScore: Double?
  public let aggregateCoreScore: Double?
  public let automaticReady: Bool
  public let bestReachableUsable: Bool

  public init(
    hardSatisfied: Bool,
    allCoreKnown: Bool,
    minimumCoreScore: Double?,
    aggregateCoreScore: Double?,
    automaticReady: Bool,
    bestReachableUsable: Bool
  ) {
    self.hardSatisfied = hardSatisfied
    self.allCoreKnown = allCoreKnown
    self.minimumCoreScore = minimumCoreScore
    self.aggregateCoreScore = aggregateCoreScore
    self.automaticReady = automaticReady
    self.bestReachableUsable = bestReachableUsable
  }
}

/// Capture readiness is intentionally non-compensatory: one very weak CORE
/// goal cannot be hidden by several excellent ones. A generalized mean plus a
/// per-goal floor gives us a smooth aggregate without fake precision.
public struct ReadinessPolicy: Sendable {
  public var automaticCoreFloor = 0.62
  public var automaticAggregateThreshold = 0.76
  public var bestReachableCoreFloor = 0.55
  public var bestReachableAggregateThreshold = 0.58
  public var generalizedMeanPower = -4.0

  public init() {}

  public func assess(
    engine: GoalEngine,
    goalGroups: [GoalGroupDefinition] = []
  ) -> ReadinessAssessment {
    let relevant = engine.states.filter { $0.value.policy != .skipped }
    let hard = relevant.filter { engine.definitions[$0.key]?.constraint == .hard }
    let core = relevant.filter { engine.definitions[$0.key]?.constraint == .core }

    let hardSatisfied = hard.allSatisfy { $0.value.state == .satisfied }
    if core.isEmpty {
      return ReadinessAssessment(
        hardSatisfied: hardSatisfied,
        allCoreKnown: true,
        minimumCoreScore: nil,
        aggregateCoreScore: nil,
        automaticReady: hardSatisfied,
        bestReachableUsable: hardSatisfied
      )
    }

    // A goal that participates in a joint/trade-off group is evaluated through
    // that group's utility surface instead of being counted independently.
    // This prevents two intentionally competing goals from each becoming a
    // separate hard floor.
    let groupedCoreIDs = Set(
      goalGroups.flatMap(\.members).map(\.goal).filter { id in
        engine.definitions[id]?.constraint == .core
      })
    let ungroupedCore = core.filter { !groupedCoreIDs.contains($0.key) }

    let knownUngrouped = ungroupedCore.compactMap { entry -> (Double, Double)? in
      guard let definition = engine.definitions[entry.key], let score = entry.value.score else {
        return nil
      }
      let weight = max(
        0.0001, definition.importance * (entry.value.policy == .deprioritized ? 0.35 : 1))
      return (min(max(score, 0), 1), weight)
    }

    let groupEvaluator = GoalGroupEvaluator()
    let relevantGroups = goalGroups.filter { group in
      group.members.contains { member in engine.definitions[member.goal]?.constraint == .core }
    }
    let groupAssessments = relevantGroups.map { groupEvaluator.assess($0, engine: engine) }

    let allUngroupedKnown = knownUngrouped.count == ungroupedCore.count
    let allGroupsKnown = groupAssessments.allSatisfy(\.known)
    let allKnown = allUngroupedKnown && allGroupsKnown

    let minScore = knownUngrouped.map(\.0).min()
    let aggregate = knownUngrouped.isEmpty ? nil : generalizedMean(knownUngrouped)

    let automaticUngrouped =
      ungroupedCore.isEmpty
      || (allUngroupedKnown
        && (minScore ?? 0) >= automaticCoreFloor
        && (aggregate ?? 0) >= automaticAggregateThreshold)
    let bestUngrouped =
      ungroupedCore.isEmpty
      || (allUngroupedKnown
        && (minScore ?? 0) >= bestReachableCoreFloor
        && (aggregate ?? 0) >= bestReachableAggregateThreshold)

    let automaticGroups = zip(relevantGroups, groupAssessments).allSatisfy { group, assessment in
      assessment.known && assessment.satisfied
    }
    let bestGroups = zip(relevantGroups, groupAssessments).allSatisfy { group, assessment in
      guard assessment.known, let score = assessment.score,
        let memberFloor = assessment.minimumMemberScore
      else { return false }
      return memberFloor >= min(group.minimumMemberScore, bestReachableCoreFloor)
        && score >= min(group.targetScore, bestReachableAggregateThreshold)
    }

    return ReadinessAssessment(
      hardSatisfied: hardSatisfied,
      allCoreKnown: allKnown,
      minimumCoreScore: minScore,
      aggregateCoreScore: aggregate,
      automaticReady: hardSatisfied && allKnown && automaticUngrouped && automaticGroups,
      bestReachableUsable: hardSatisfied && allKnown && bestUngrouped && bestGroups
    )
  }

  private func generalizedMean(_ values: [(Double, Double)]) -> Double {
    let p = generalizedMeanPower
    let epsilon = 0.0001
    let weightSum = values.reduce(0.0) { $0 + $1.1 }
    guard weightSum > 0 else { return 0 }
    if abs(p) < 0.000_001 {
      let logMean = values.reduce(0.0) { $0 + $1.1 * log(max($1.0, epsilon)) } / weightSum
      return exp(logMean)
    }
    let powered =
      values.reduce(0.0) {
        $0 + $1.1 * pow(max($1.0, epsilon), p)
      } / weightSum
    return pow(powered, 1 / p)
  }
}
