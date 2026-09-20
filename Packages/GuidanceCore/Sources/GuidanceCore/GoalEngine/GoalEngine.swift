import Foundation

public final class GoalEngine {
    public let definitions: [GoalID: GoalDefinition]
    public private(set) var states: [GoalID: GoalRuntimeState]
    public let graph: DependencyGraph

    /// Optional runtime overrides used by deterministic tests and recipe-wide tuning.
    /// A value of zero uses the policy carried by each goal definition.
    public var enterFrames = 0
    public var exitFrames = 0
    public var minimumConfidence = 0.5

    public init(_ definitions: [GoalDefinition]) {
        self.definitions = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        states = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, GoalRuntimeState()) })
        graph = DependencyGraph(definitions)
    }

    @discardableResult
    public func ingest(_ observation: Observation) -> GoalID? {
        ingestAll(observation).first
    }

    @discardableResult
    public func ingestAll(_ observation: Observation) -> [GoalID] {
        let matching = definitions.values.filter {
            $0.dimension == observation.dimension && $0.binding == observation.binding
        }

        for definition in matching {
            update(definition, with: observation)
        }

        return matching.map(\.id)
    }

    public func markDirty(_ id: GoalID) {
        states[id]?.dirty = true
    }

    public func clearDirty(_ id: GoalID) {
        states[id]?.dirty = false
    }

    public func propagateDirty(from id: GoalID) {
        for dependent in graph.dependents(of: id) {
            states[dependent]?.dirty = true
        }
    }

    public func setPolicy(_ policy: UserGoalPolicy, for id: GoalID) {
        states[id]?.policy = policy
    }

    public func setState(_ state: GoalState, for id: GoalID) {
        states[id]?.state = state
    }

    private func update(_ definition: GoalDefinition, with observation: Observation) {
        guard var runtime = states[definition.id] else { return }

        runtime.dirty = false
        runtime.confidence = observation.confidence
        runtime.lastUpdatedFrame = observation.frameID

        guard observation.confidence >= minimumConfidence else {
            runtime.state = .unknown
            runtime.score = nil
            runtime.enterCounter = 0
            runtime.exitCounter = 0
            states[definition.id] = runtime
            return
        }

        let evaluation = Scoring.evaluate(observation, target: definition.target)
        guard evaluation.state != .unknown else {
            runtime.state = .unknown
            runtime.score = nil
            runtime.enterCounter = 0
            runtime.exitCounter = 0
            states[definition.id] = runtime
            return
        }

        runtime.score = evaluation.score
        let enterThreshold = definition.stability.enterThreshold
        let exitThreshold = definition.stability.exitThreshold
        let requiredEnterFrames = enterFrames > 0
            ? enterFrames
            : definition.stability.enterFrames
        let requiredExitFrames = exitFrames > 0
            ? exitFrames
            : definition.stability.exitFrames

        if evaluation.score >= enterThreshold {
            runtime.enterCounter += 1
            runtime.exitCounter = 0
            if runtime.enterCounter >= requiredEnterFrames {
                runtime.state = .satisfied
            }
        } else if evaluation.score < exitThreshold {
            runtime.exitCounter += 1
            runtime.enterCounter = 0
            if runtime.exitCounter >= requiredExitFrames {
                runtime.state = runtime.state == .satisfied ? .drifted : .active
            }
        } else {
            // The hysteresis band intentionally preserves the current stable state.
            runtime.enterCounter = 0
            runtime.exitCounter = 0
        }

        states[definition.id] = runtime
    }
}
