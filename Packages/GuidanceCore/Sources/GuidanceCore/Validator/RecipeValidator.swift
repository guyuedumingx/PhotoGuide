import Foundation

public enum ValidationSeverity: String, Codable, Sendable { case error, warning, info }

public enum ValidationRule: String, Sendable {
  case duplicateGoalID
  case duplicateActionID
  case duplicateRegistryID
  case missingDimensionReference
  case missingBindingReference
  case missingEvaluatorReference
  case evaluatorDoesNotSupportDimension
  case invalidActionGoalReference
  case missingRelationParticipant
  case duplicateRelationRole
  case incompatibleBindingScope
  case missingDependencyReference
  case contradictoryGoals
  case hardDependencyCycle
  case missingActionCoverage
  case impossibleReadiness
  case trivialReadiness
  case unsafeOnlyRequiredActions
  case invalidCancellationRestriction
  case invalidTargetType
  case invalidTargetRange
  case invalidDimensionValueSpace
  case targetOutsideDimensionSpace
  case unobservableDimension
  case requiredNodeWithoutPresenceGoal
  case duplicateActionEffectGoal
  case duplicateInformationEffectGoal
  case actionWithoutPositiveEffect
  case unsafeMovementDeclaredSafe
  case invalidActionMetadata
  case invalidGoalImportance
  case invalidActionNumeric
  case duplicateGoalGroupID
  case missingGoalGroupMember
  case duplicateGoalGroupMember
  case invalidGoalGroupConfiguration
  case overlappingCriticalGoalGroups
  case simulationCannotConverge
}

public struct ValidationIssue: Equatable, Sendable {
  public let rule: ValidationRule
  public let severity: ValidationSeverity
  public let message: String

  public init(rule: ValidationRule, severity: ValidationSeverity, message: String) {
    self.rule = rule
    self.severity = severity
    self.message = message
  }
}

public struct RecipeValidator: Sendable {
  public init() {}

  public func validate(
    goals: [GoalDefinition],
    actions: [ActionDefinition],
    registry: GuidanceRegistry,
    goalGroups: [GoalGroupDefinition] = [],
    cancellationAllowed: Bool = true
  ) -> [ValidationIssue] {
    var issues = [ValidationIssue]()
    let goalIDs = Set(goals.map(\.id))

    for duplicate in duplicates(goals.map(\.id)) {
      issues.append(.init(rule: .duplicateGoalID, severity: .error, message: duplicate.rawValue))
    }
    for duplicate in duplicates(actions.map(\.id)) {
      issues.append(.init(rule: .duplicateActionID, severity: .error, message: duplicate.rawValue))
    }
    for issue in registry.integrityIssues {
      issues.append(
        .init(rule: .duplicateRegistryID, severity: .error, message: String(describing: issue)))
    }

    for duplicate in duplicates(goalGroups.map(\.id)) {
      issues.append(
        .init(rule: .duplicateGoalGroupID, severity: .error, message: duplicate.rawValue))
    }

    var criticalMembership = [GoalID: Int]()
    for group in goalGroups {
      let memberIDs = group.members.map(\.goal)
      for duplicate in duplicates(memberIDs) {
        issues.append(
          .init(
            rule: .duplicateGoalGroupMember, severity: .error,
            message: "\(group.id.rawValue):\(duplicate.rawValue)"))
      }
      if group.members.count < 2
        || group.members.allSatisfy({ $0.weight <= 0 })
        || group.minimumMemberScore > group.targetScore
      {
        issues.append(
          .init(
            rule: .invalidGoalGroupConfiguration, severity: .error, message: group.id.rawValue))
      }
      for member in group.members {
        guard goalIDs.contains(member.goal) else {
          issues.append(
            .init(
              rule: .missingGoalGroupMember, severity: .error,
              message: "\(group.id.rawValue):\(member.goal.rawValue)"))
          continue
        }
        if goals.first(where: { $0.id == member.goal })?.constraint != .soft {
          criticalMembership[member.goal, default: 0] += 1
        }
      }
    }
    for (goalID, count) in criticalMembership where count > 1 {
      issues.append(
        .init(
          rule: .overlappingCriticalGoalGroups, severity: .error, message: goalID.rawValue))
    }

    for goal in goals {
      guard let dimension = registry.dimensions[goal.dimension] else {
        issues.append(
          .init(
            rule: .missingDimensionReference, severity: .error, message: goal.dimension.rawValue))
        continue
      }
      if !binding(goal.binding, matches: dimension.scope) {
        issues.append(
          .init(rule: .incompatibleBindingScope, severity: .error, message: goal.id.rawValue))
      }
      if !target(goal.target, matches: dimension.valueType) {
        issues.append(.init(rule: .invalidTargetType, severity: .error, message: goal.id.rawValue))
      }
      if let valueSpace = dimension.valueSpace {
        if !valueSpace.isWellFormed || valueSpace.valueType != dimension.valueType {
          issues.append(
            .init(
              rule: .invalidDimensionValueSpace, severity: .error, message: dimension.id.rawValue))
        } else if !target(goal.target, fits: valueSpace) {
          issues.append(
            .init(
              rule: .targetOutsideDimensionSpace, severity: .error, message: goal.id.rawValue))
        }
      }
      if case .band(let band) = goal.target, !band.isWellFormed {
        issues.append(.init(rule: .invalidTargetRange, severity: .error, message: goal.id.rawValue))
      }
      if !bindingReferenceExists(goal.binding, registry: registry) {
        issues.append(
          .init(rule: .missingBindingReference, severity: .error, message: goal.id.rawValue))
      }
      if dimension.evaluatorIDs.isEmpty && dimension.controlClass == .control {
        issues.append(
          .init(rule: .unobservableDimension, severity: .warning, message: goal.dimension.rawValue))
      }
      for evaluatorID in dimension.evaluatorIDs {
        guard let evaluator = registry.evaluators[evaluatorID] else {
          issues.append(
            .init(
              rule: .missingEvaluatorReference, severity: .error,
              message: "\(goal.dimension.rawValue):\(evaluatorID.rawValue)"))
          continue
        }
        if !evaluator.supportedDimensions.isEmpty,
          !evaluator.supportedDimensions.contains(goal.dimension)
        {
          issues.append(
            .init(
              rule: .evaluatorDoesNotSupportDimension, severity: .error,
              message: "\(evaluatorID.rawValue):\(goal.dimension.rawValue)"))
        }
      }
    }

    for goal in goals {
      for dependency in goal.dependencies where !goalIDs.contains(dependency) {
        issues.append(
          .init(rule: .missingDependencyReference, severity: .error, message: dependency.rawValue))
      }
    }

    for relation in registry.relations.values {
      for participant in relation.participants where registry.nodes[participant.node] == nil {
        issues.append(
          .init(
            rule: .missingRelationParticipant, severity: .error,
            message: "\(relation.id.rawValue):\(participant.node.rawValue)"))
      }
      let duplicateRoles = duplicates(relation.participants.map(\.role))
      for role in duplicateRoles {
        issues.append(
          .init(
            rule: .duplicateRelationRole, severity: .error,
            message: "\(relation.id.rawValue):\(role)"))
      }
    }

    for action in actions {
      for ref in action.touchedGoals.union(action.informationGoals) where !goalIDs.contains(ref) {
        issues.append(
          .init(
            rule: .invalidActionGoalReference, severity: .error,
            message: "\(action.id.rawValue):\(ref.rawValue)"))
      }
      if let conditionGoal = conditionGoalID(action.condition), !goalIDs.contains(conditionGoal) {
        issues.append(
          .init(
            rule: .invalidActionGoalReference, severity: .error,
            message: "\(action.id.rawValue):\(conditionGoal.rawValue)"))
      }
      for duplicate in duplicates(action.effects.map(\.goal)) {
        issues.append(
          .init(
            rule: .duplicateActionEffectGoal, severity: .error,
            message: "\(action.id.rawValue):\(duplicate.rawValue)"))
      }
      for duplicate in duplicates(action.informationEffects.map(\.goal)) {
        issues.append(
          .init(
            rule: .duplicateInformationEffectGoal, severity: .error,
            message: "\(action.id.rawValue):\(duplicate.rawValue)"))
      }
      if action.improvedGoals.isEmpty, !action.isInformationSeeking,
        action.operation != .hold, action.operation != .wait, action.operation != .capture,
        action.operation != .selectAnchor
      {
        issues.append(
          .init(
            rule: .actionWithoutPositiveEffect, severity: .warning, message: action.id.rawValue))
      }
      if action.actor == .photographer, action.operation == .move, action.direction == .backward,
        action.safety == .safe
      {
        issues.append(
          .init(
            rule: .unsafeMovementDeclaredSafe, severity: .error, message: action.id.rawValue))
      }
      if action.family.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || action.presentationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        issues.append(
          .init(
            rule: .invalidActionMetadata, severity: .error, message: action.id.rawValue))
      }
    }

    if DependencyGraph(goals).hasCycle() {
      issues.append(
        .init(rule: .hardDependencyCycle, severity: .error, message: "dependency cycle"))
    }

    if goals.allSatisfy({ $0.constraint == .soft }) {
      issues.append(
        .init(rule: .trivialReadiness, severity: .warning, message: "recipe has no HARD/CORE goals")
      )
    }

    for goal in goals where goal.constraint != .soft {
      let covering = actions.filter { $0.improvedGoals.contains(goal.id) }
      if covering.isEmpty {
        issues.append(
          .init(rule: .missingActionCoverage, severity: .warning, message: goal.id.rawValue))
        if goal.constraint == .hard {
          issues.append(
            .init(rule: .impossibleReadiness, severity: .error, message: goal.id.rawValue))
        }
      } else if goal.constraint == .hard && covering.allSatisfy({ $0.safety == .restricted }) {
        issues.append(
          .init(rule: .unsafeOnlyRequiredActions, severity: .error, message: goal.id.rawValue))
      }
    }

    let grouped = Dictionary(grouping: goals) {
      GoalBindingKey(dimension: $0.dimension, binding: $0.binding)
    }
    for group in grouped.values where containsContradiction(group) {
      issues.append(
        .init(
          rule: .contradictoryGoals, severity: .error,
          message: group.map { $0.id.rawValue }.joined(separator: ",")))
    }

    for node in registry.nodes.values where node.presence == .required {
      let hasPresenceGoal = goals.contains { goal in
        guard goal.binding == .node(node.id) else { return false }
        return goal.dimension.rawValue == "std.node.exists" && goal.constraint == .hard
      }
      if !hasPresenceGoal {
        issues.append(
          .init(
            rule: .requiredNodeWithoutPresenceGoal, severity: .warning,
            message: node.id.rawValue))
      }
    }

    let simulation = RecipeSimulationAnalyzer().simulate(
      goals: goals, actions: actions, goalGroups: goalGroups)
    if !simulation.converged, !simulation.unresolvedCriticalGoals.isEmpty {
      issues.append(
        .init(
          rule: .simulationCannotConverge, severity: .warning,
          message: simulation.unresolvedCriticalGoals.map(\.rawValue).sorted().joined(
            separator: ",")
        ))
    }

    if !cancellationAllowed {
      issues.append(
        .init(
          rule: .invalidCancellationRestriction, severity: .error,
          message: "cancel must remain available"))
    }
    return issues
  }

  private func binding(_ binding: Binding, matches scope: DimensionScope) -> Bool {
    switch (binding, scope) {
    case (.node, .node), (.relation, .relation), (.frame, .frame), (.capture, .capture): true
    default: false
    }
  }

  private func bindingReferenceExists(_ binding: Binding, registry: GuidanceRegistry) -> Bool {
    switch binding {
    case .node(let id): registry.nodes[id] != nil
    case .relation(let id): registry.relations[id] != nil
    case .frame, .capture: true
    }
  }

  private func conditionGoalID(_ condition: ActionCondition) -> GoalID? {
    switch condition {
    case .always: nil
    case .goalUnsatisfied(let id): id
    case .continuousBelow(let id, _): id
    case .continuousAbove(let id, _): id
    case .ordinalBelow(let id, _): id
    case .ordinalAbove(let id, _): id
    case .booleanEquals(let id, _): id
    }
  }

  private func target(_ target: GoalTarget, matches type: DimensionValueType) -> Bool {
    switch (target, type) {
    case (.band, .continuous), (.ordinal, .ordinal), (.categorical, .categorical),
      (.boolean, .boolean):
      true
    default: false
    }
  }

  private func target(_ target: GoalTarget, fits space: DimensionValueSpace) -> Bool {
    switch (target, space) {
    case (.boolean, .boolean):
      true
    case (.categorical(let value), .categorical(let values)):
      values.contains(value)
    case (.ordinal(let value), .ordinal(let min, let max)):
      value >= min && value <= max
    case (.band(let band), .continuous(let min, let max, _)):
      band.isWellFormed
        && band.acceptable.lowerBound >= min
        && band.acceptable.upperBound <= max
        && band.ideal.lowerBound >= min
        && band.ideal.upperBound <= max
    default:
      false
    }
  }

  private func containsContradiction(_ goals: [GoalDefinition]) -> Bool {
    let hard = goals.filter { $0.constraint == .hard }
    for i in hard.indices {
      for j in hard.indices where j > i {
        if targetsConflict(hard[i].target, hard[j].target) { return true }
      }
    }
    return false
  }

  private func targetsConflict(_ lhs: GoalTarget, _ rhs: GoalTarget) -> Bool {
    switch (lhs, rhs) {
    case (.boolean(let a), .boolean(let b)): a != b
    case (.categorical(let a), .categorical(let b)): a != b
    case (.ordinal(let a), .ordinal(let b)): a != b
    case (.band(let a), .band(let b)): !a.acceptable.overlaps(b.acceptable)
    default: true
    }
  }

  private func duplicates<T: Hashable>(_ values: [T]) -> Set<T> {
    var seen = Set<T>()
    var duplicate = Set<T>()
    for value in values {
      if !seen.insert(value).inserted { duplicate.insert(value) }
    }
    return duplicate
  }
}

private struct GoalBindingKey: Hashable {
  let dimension: DimensionID
  let binding: Binding
}
