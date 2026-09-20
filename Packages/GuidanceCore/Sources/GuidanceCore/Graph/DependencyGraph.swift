import Foundation

public struct DependencyGraph: Sendable {
    public let dependencies: [GoalID: Set<GoalID>]

    public init(_ goals: [GoalDefinition]) {
        dependencies = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0.dependencies) })
    }

    public func dependents(of id: GoalID) -> Set<GoalID> {
        var found = Set<GoalID>()
        var queue = [id]

        while let current = queue.popLast() {
            for (goal, parents) in dependencies
            where parents.contains(current) && !found.contains(goal) {
                found.insert(goal)
                queue.append(goal)
            }
        }

        return found
    }

    public func hasCycle() -> Bool {
        var visiting = Set<GoalID>()
        var visited = Set<GoalID>()

        func visit(_ id: GoalID) -> Bool {
            if visiting.contains(id) { return true }
            if visited.contains(id) { return false }

            visiting.insert(id)
            for dependency in dependencies[id] ?? [] where visit(dependency) {
                return true
            }
            visiting.remove(id)
            visited.insert(id)
            return false
        }

        return dependencies.keys.contains(where: visit)
    }
}
