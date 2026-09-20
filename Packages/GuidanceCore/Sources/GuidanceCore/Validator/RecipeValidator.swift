import Foundation

public enum ValidationRule: String, Sendable {
    case missingDimensionReference
    case missingDependencyReference
    case contradictoryGoals
    case hardDependencyCycle
    case missingActionCoverage
    case impossibleReadiness
    case trivialReadiness
    case unsafeOnlyRequiredActions
    case invalidCancellationRestriction
}

public struct ValidationIssue: Equatable, Sendable {
    public let rule: ValidationRule
    public let message: String

    public init(rule: ValidationRule, message: String) {
        self.rule = rule
        self.message = message
    }
}

public struct RecipeValidator: Sendable {
    public init() {}

    public func validate(
        goals: [GoalDefinition],
        dimensions: Set<DimensionID>,
        actions: [ActionDefinition],
        cancellationAllowed: Bool = true
    ) -> [ValidationIssue] {
        var issues = [ValidationIssue]()
        let goalIDs = Set(goals.map(\.id))

        for goal in goals where !dimensions.contains(goal.dimension) {
            issues.append(.init(rule: .missingDimensionReference, message: goal.id.rawValue))
        }

        for goal in goals {
            for dependency in goal.dependencies where !goalIDs.contains(dependency) {
                issues.append(.init(rule: .missingDependencyReference, message: dependency.rawValue))
            }
        }

        if DependencyGraph(goals).hasCycle() {
            issues.append(.init(rule: .hardDependencyCycle, message: "dependency cycle"))
        }

        let hardOrCore = goals.filter { $0.constraint != .soft }
        if hardOrCore.isEmpty {
            issues.append(.init(rule: .trivialReadiness, message: "no hard or core goals"))
        }

        for goal in goals {
            let coveringActions = actions.filter { $0.affects.contains(goal.id) }
            if coveringActions.isEmpty {
                issues.append(.init(rule: .missingActionCoverage, message: goal.id.rawValue))
                if goal.constraint == .hard {
                    issues.append(.init(rule: .impossibleReadiness, message: goal.id.rawValue))
                }
            } else if goal.constraint == .hard && coveringActions.allSatisfy({ !$0.safe }) {
                issues.append(.init(rule: .unsafeOnlyRequiredActions, message: goal.id.rawValue))
                issues.append(.init(rule: .impossibleReadiness, message: goal.id.rawValue))
            }
        }

        let grouped = Dictionary(grouping: goals) { goal in
            GoalBindingKey(dimension: goal.dimension, binding: goal.binding)
        }
        for group in grouped.values where containsContradiction(group) {
            let ids = group.map { $0.id.rawValue }.joined(separator: ",")
            issues.append(.init(rule: .contradictoryGoals, message: ids))
        }

        if !cancellationAllowed {
            issues.append(.init(rule: .invalidCancellationRestriction, message: "cancel must be allowed"))
        }

        return issues
    }

    private func containsContradiction(_ goals: [GoalDefinition]) -> Bool {
        let hardGoals = goals.filter { $0.constraint == .hard }
        for leftIndex in hardGoals.indices {
            for rightIndex in hardGoals.indices where rightIndex > leftIndex {
                if targetsConflict(hardGoals[leftIndex].target, hardGoals[rightIndex].target) {
                    return true
                }
            }
        }
        return false
    }

    private func targetsConflict(_ lhs: GoalTarget, _ rhs: GoalTarget) -> Bool {
        switch (lhs, rhs) {
        case let (.boolean(left), .boolean(right)):
            return left != right
        case let (.categorical(left), .categorical(right)):
            return left != right
        case let (.ordinal(left), .ordinal(right)):
            return left != right
        case let (.band(left), .band(right)):
            return !left.acceptable.overlaps(right.acceptable)
        default:
            return true
        }
    }
}

private struct GoalBindingKey: Hashable {
    let dimension: DimensionID
    let binding: Binding
}
