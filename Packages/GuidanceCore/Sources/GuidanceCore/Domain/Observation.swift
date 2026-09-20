import Foundation

public enum DimensionValue: Codable, Equatable, Sendable {
    case continuous(Double)
    case ordinal(Int)
    case categorical(String)
    case boolean(Bool)
}

public struct Binding: Codable, Hashable, Sendable {
    public let nodes: [NodeID]

    public init(_ nodes: [NodeID]) {
        self.nodes = nodes
    }
}

public struct Observation: Codable, Equatable, Sendable {
    public let dimension: DimensionID
    public let binding: Binding
    public let value: DimensionValue
    public let confidence: Double
    public let evaluator: EvaluatorID
    public let distribution: [String: Double]?
    public let frameID: Int
    public let timestamp: Date
    public let bindingVersion: Int
    public let sceneRevision: Int

    public init(
        dimension: DimensionID,
        binding: Binding,
        value: DimensionValue,
        confidence: Double,
        evaluator: EvaluatorID = EvaluatorID("local"),
        distribution: [String: Double]? = nil,
        frameID: Int,
        timestamp: Date,
        bindingVersion: Int = 0,
        sceneRevision: Int = 0
    ) {
        self.dimension = dimension
        self.binding = binding
        self.value = value
        self.confidence = min(max(confidence, 0), 1)
        self.evaluator = evaluator
        self.distribution = distribution
        self.frameID = frameID
        self.timestamp = timestamp
        self.bindingVersion = bindingVersion
        self.sceneRevision = sceneRevision
    }
}
