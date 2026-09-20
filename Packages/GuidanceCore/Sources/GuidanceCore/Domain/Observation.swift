import Foundation

public enum DimensionValue: Codable, Equatable, Sendable {
  case continuous(Double)
  case ordinal(Int)
  case categorical(String)
  case boolean(Bool)
}

public enum Binding: Codable, Hashable, Sendable {
  case node(NodeID)
  case relation(RelationID)
  case frame
  case capture

  public var nodeIDs: [NodeID] {
    switch self {
    case .node(let id): [id]
    default: []
    }
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
    timestamp: Date = .now,
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
