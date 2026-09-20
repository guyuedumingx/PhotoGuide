import Foundation

public struct DependencyGraph: Sendable {
  public let dependencies: [GoalID: Set<GoalID>]

  public init(_ goals: [GoalDefinition]) {
    var map = [GoalID: Set<GoalID>]()
    for goal in goals { map[goal.id] = goal.dependencies }
    dependencies = map
  }

  public func directDependents(of id: GoalID) -> Set<GoalID> {
    Set(dependencies.compactMap { goal, parents in parents.contains(id) ? goal : nil })
  }

  public func dependents(of id: GoalID) -> Set<GoalID> {
    var found = Set<GoalID>()
    var queue = [id]
    while let current = queue.popLast() {
      for goal in directDependents(of: current) where !found.contains(goal) {
        found.insert(goal)
        queue.append(goal)
      }
    }
    return found
  }

  public func hasCycle() -> Bool { topologicalOrder() == nil }

  /// Stable topological order. Unknown dependency IDs are ignored here and are
  /// reported by RecipeValidator; the engine must still remain crash-safe.
  public func topologicalOrder() -> [GoalID]? {
    let ids = Set(dependencies.keys)
    var indegree = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
    var children = [GoalID: Set<GoalID>]()

    for (goal, parents) in dependencies {
      for parent in parents where ids.contains(parent) {
        indegree[goal, default: 0] += 1
        children[parent, default: []].insert(goal)
      }
    }

    var ready = indegree.filter { $0.value == 0 }.map(\.key)
      .sorted { $0.rawValue < $1.rawValue }
    var result = [GoalID]()

    while !ready.isEmpty {
      let next = ready.removeFirst()
      result.append(next)
      let sortedChildren = (children[next] ?? []).sorted { $0.rawValue < $1.rawValue }
      for child in sortedChildren {
        indegree[child, default: 0] -= 1
        if indegree[child] == 0 {
          ready.append(child)
          ready.sort { $0.rawValue < $1.rawValue }
        }
      }
    }

    return result.count == ids.count ? result : nil
  }
}
