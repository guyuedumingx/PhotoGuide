import Foundation

public enum NodeType: String, Codable, Sendable {
  case entity
  case entityGroup
  case region
  case surface
  case text
  case geometry
  case lightSource
}

public enum PresencePolicy: String, Codable, Sendable {
  case required
  case optional
  case substitutable
  case ignore
}

public struct NodeDefinition: Codable, Equatable, Sendable {
  public let id: NodeID
  public let type: NodeType
  public let semanticClass: String?
  public let roles: Set<String>
  public let presence: PresencePolicy

  public init(
    id: NodeID,
    type: NodeType,
    semanticClass: String? = nil,
    roles: Set<String> = [],
    presence: PresencePolicy = .optional
  ) {
    self.id = id
    self.type = type
    self.semanticClass = semanticClass
    self.roles = roles
    self.presence = presence
  }
}

public struct RelationParticipant: Codable, Equatable, Sendable {
  public let role: String
  public let node: NodeID

  public init(role: String, node: NodeID) {
    self.role = role
    self.node = node
  }
}

public struct RelationDefinition: Codable, Equatable, Sendable {
  public let id: RelationID
  public let type: String
  public let participants: [RelationParticipant]
  public let directed: Bool

  public init(
    id: RelationID,
    type: String,
    participants: [RelationParticipant],
    directed: Bool = true
  ) {
    self.id = id
    self.type = type
    self.participants = participants
    self.directed = directed
  }
}

public enum DimensionScope: String, Codable, Sendable {
  case node
  case relation
  case frame
  case capture
}

public enum DimensionValueType: String, Codable, Sendable {
  case continuous
  case ordinal
  case categorical
  case boolean
}

public enum DimensionValueSpace: Codable, Equatable, Sendable {
  case continuous(min: Double, max: Double, unit: String?)
  case ordinal(min: Int, max: Int)
  case categorical(values: Set<String>)
  case boolean

  public var valueType: DimensionValueType {
    switch self {
    case .continuous: .continuous
    case .ordinal: .ordinal
    case .categorical: .categorical
    case .boolean: .boolean
    }
  }

  public var isWellFormed: Bool {
    switch self {
    case .continuous(let min, let max, _): min.isFinite && max.isFinite && min <= max
    case .ordinal(let min, let max): min <= max
    case .categorical(let values): !values.isEmpty && values.allSatisfy { !$0.isEmpty }
    case .boolean: true
    }
  }

  public func contains(_ value: DimensionValue) -> Bool {
    switch (self, value) {
    case (.continuous(let min, let max, _), .continuous(let value)):
      value.isFinite && value >= min && value <= max
    case (.ordinal(let min, let max), .ordinal(let value)):
      value >= min && value <= max
    case (.categorical(let values), .categorical(let value)):
      values.contains(value)
    case (.boolean, .boolean):
      true
    default:
      false
    }
  }
}

public enum DimensionControlClass: String, Codable, Sendable {
  case control
  case diagnostic
  case finalScore
}

public enum DimensionValidationStatus: String, Codable, Sendable {
  case draft
  case experimental
  case calibrating
  case communityValidated
  case standard
}

public struct DimensionDefinition: Codable, Equatable, Sendable {
  public let id: DimensionID
  public let name: String
  public let description: String
  public let scope: DimensionScope
  public let valueType: DimensionValueType
  public let valueSpace: DimensionValueSpace?
  public let controlClass: DimensionControlClass
  public let actionability: Double
  public let validationStatus: DimensionValidationStatus
  public let evaluatorIDs: Set<EvaluatorID>

  public init(
    id: DimensionID,
    name: String,
    description: String,
    scope: DimensionScope,
    valueType: DimensionValueType,
    valueSpace: DimensionValueSpace? = nil,
    controlClass: DimensionControlClass = .control,
    actionability: Double = 1,
    validationStatus: DimensionValidationStatus = .standard,
    evaluatorIDs: Set<EvaluatorID> = []
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.scope = scope
    self.valueType = valueType
    self.valueSpace = valueSpace
    self.controlClass = controlClass
    self.actionability = min(max(actionability, 0), 1)
    self.validationStatus = validationStatus
    self.evaluatorIDs = evaluatorIDs
  }
}

public enum EvaluatorLatencyClass: String, Codable, Sendable { case realtime, fast, medium, slow }
public enum EvaluatorCostClass: String, Codable, Sendable { case veryLow, low, medium, high }
public enum EvaluatorKind: String, Codable, Sendable {
  case localVision
  case localTelemetry
  case temporal
  case semanticRemote
  case fusion
  case other
}

public struct EvaluatorDefinition: Codable, Equatable, Sendable {
  public let id: EvaluatorID
  public let supportedDimensions: Set<DimensionID>
  public let kind: EvaluatorKind
  public let latency: EvaluatorLatencyClass
  public let cost: EvaluatorCostClass
  public let supportsConfidence: Bool
  public let supportsDistribution: Bool
  public let defaultReliability: Double

  public init(
    id: EvaluatorID,
    supportedDimensions: Set<DimensionID>,
    kind: EvaluatorKind = .other,
    latency: EvaluatorLatencyClass,
    cost: EvaluatorCostClass,
    supportsConfidence: Bool = true,
    supportsDistribution: Bool = false,
    defaultReliability: Double = 0.85
  ) {
    self.id = id
    self.supportedDimensions = supportedDimensions
    self.kind = kind
    self.latency = latency
    self.cost = cost
    self.supportsConfidence = supportsConfidence
    self.supportsDistribution = supportsDistribution
    self.defaultReliability = min(max(defaultReliability, 0), 1)
  }
}
