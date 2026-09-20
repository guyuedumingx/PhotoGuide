import Foundation

public enum RegistryIntegrityIssue: Equatable, Sendable {
  case duplicateNode(NodeID)
  case duplicateRelation(RelationID)
  case duplicateDimension(DimensionID)
  case duplicateEvaluator(EvaluatorID)
}

public struct GuidanceRegistry: Sendable {
  public let nodes: [NodeID: NodeDefinition]
  public let relations: [RelationID: RelationDefinition]
  public let dimensions: [DimensionID: DimensionDefinition]
  public let evaluators: [EvaluatorID: EvaluatorDefinition]
  public let integrityIssues: [RegistryIntegrityIssue]

  public init(
    nodes: [NodeDefinition] = [],
    relations: [RelationDefinition] = [],
    dimensions: [DimensionDefinition] = [],
    evaluators: [EvaluatorDefinition] = []
  ) {
    var issues = [RegistryIntegrityIssue]()
    self.nodes = Self.index(nodes, id: \.id) { issues.append(.duplicateNode($0)) }
    self.relations = Self.index(relations, id: \.id) { issues.append(.duplicateRelation($0)) }
    self.dimensions = Self.index(dimensions, id: \.id) { issues.append(.duplicateDimension($0)) }
    self.evaluators = Self.index(evaluators, id: \.id) { issues.append(.duplicateEvaluator($0)) }
    self.integrityIssues = issues
  }

  private static func index<T, ID: Hashable>(
    _ values: [T],
    id: KeyPath<T, ID>,
    onDuplicate: (ID) -> Void
  ) -> [ID: T] {
    var result = [ID: T]()
    for value in values {
      let key = value[keyPath: id]
      if result[key] != nil { onDuplicate(key) }
      result[key] = value
    }
    return result
  }

  public static let standardPhotography = GuidanceRegistry(
    dimensions: [
      .init(
        id: DimensionID("std.node.exists"), name: "存在", description: "目标节点是否存在", scope: .node,
        valueType: .boolean, valueSpace: .boolean, evaluatorIDs: [EvaluatorID("vision.local")]),
      .init(
        id: DimensionID("std.node.visibility"), name: "完整可见", description: "目标节点是否完整留在画面内",
        scope: .node, valueType: .boolean, valueSpace: .boolean,
        evaluatorIDs: [EvaluatorID("vision.local")]),
      .init(
        id: DimensionID("std.node.visual_scale"), name: "视觉大小", description: "目标节点占画面的面积比例",
        scope: .node, valueType: .continuous,
        valueSpace: .continuous(min: 0, max: 1, unit: "frame_ratio"),
        evaluatorIDs: [EvaluatorID("vision.local")]),
      .init(
        id: DimensionID("std.node.position_x"), name: "水平位置", description: "目标节点中心的水平位置",
        scope: .node, valueType: .continuous,
        valueSpace: .continuous(min: 0, max: 1, unit: "normalized_x"),
        evaluatorIDs: [EvaluatorID("vision.local")]),
      .init(
        id: DimensionID("std.node.position_y"), name: "垂直位置", description: "目标节点中心的垂直位置",
        scope: .node, valueType: .continuous,
        valueSpace: .continuous(min: 0, max: 1, unit: "normalized_y"),
        evaluatorIDs: [EvaluatorID("vision.local")]),
      .init(
        id: DimensionID("std.pose.body_orientation"), name: "身体朝向", description: "人物身体相对镜头的可见朝向",
        scope: .node, valueType: .ordinal, valueSpace: .ordinal(min: -2, max: 2),
        actionability: 0.85,
        evaluatorIDs: [EvaluatorID("vision.local"), EvaluatorID("djev.semantic")]),
      .init(
        id: DimensionID("std.relation.relative_scale"), name: "人景比例", description: "人物与场景主体的相对视觉尺度",
        scope: .relation, valueType: .ordinal, valueSpace: .ordinal(min: -2, max: 2),
        actionability: 0.8,
        evaluatorIDs: [EvaluatorID("vision.saliency_relation"), EvaluatorID("djev.semantic")]),
      .init(
        id: DimensionID("std.relation.visual_balance"), name: "视觉平衡",
        description: "人物与场景主体共同形成的画面平衡", scope: .relation, valueType: .ordinal,
        valueSpace: .ordinal(min: -2, max: 2),
        controlClass: .diagnostic, actionability: 0.55,
        evaluatorIDs: [EvaluatorID("vision.saliency_relation"), EvaluatorID("djev.semantic")]),
    ],
    evaluators: [
      .init(
        id: EvaluatorID("vision.local"),
        supportedDimensions: [
          DimensionID("std.node.exists"),
          DimensionID("std.node.visibility"),
          DimensionID("std.node.visual_scale"),
          DimensionID("std.node.position_x"),
          DimensionID("std.node.position_y"),
          DimensionID("std.pose.body_orientation"),
        ],
        kind: .localVision,
        latency: .realtime,
        cost: .veryLow,
        defaultReliability: 0.92
      ),
      .init(
        id: EvaluatorID("vision.saliency_relation"),
        supportedDimensions: [
          DimensionID("std.relation.relative_scale"),
          DimensionID("std.relation.visual_balance"),
        ],
        kind: .localVision,
        latency: .fast,
        cost: .veryLow,
        defaultReliability: 0.68
      ),
      .init(
        id: EvaluatorID("djev.semantic"),
        supportedDimensions: [
          DimensionID("std.pose.body_orientation"),
          DimensionID("std.relation.relative_scale"),
          DimensionID("std.relation.visual_balance"),
        ],
        kind: .semanticRemote,
        latency: .medium,
        cost: .medium,
        supportsConfidence: true,
        supportsDistribution: true,
        defaultReliability: 0.90
      ),
      .init(
        id: EvaluatorID("core.fusion"),
        supportedDimensions: [],
        kind: .fusion,
        latency: .realtime,
        cost: .veryLow,
        supportsConfidence: true,
        supportsDistribution: true,
        defaultReliability: 1.0
      ),
    ]
  )
}
