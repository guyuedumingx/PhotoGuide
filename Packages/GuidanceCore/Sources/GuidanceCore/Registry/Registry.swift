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

  /// Standard photography vocabulary shared by every shipping Recipe.
  ///
  /// The registry intentionally separates generic visual measurements from
  /// subject-specific semantic judgments. A flower, plate of food, building,
  /// pet, person, or user-selected object can all use the same node geometry
  /// dimensions. Portrait-only concepts (for example body orientation) remain
  /// optional dimensions rather than assumptions baked into the controller.
  public static let standardPhotography = GuidanceRegistry(
    dimensions: [
      .init(
        id: DimensionID("std.node.exists"), name: "目标存在", description: "目标节点是否被可靠观测到", scope: .node,
        valueType: .boolean, valueSpace: .boolean,
        evaluatorIDs: [EvaluatorID("vision.local"), EvaluatorID("vision.saliency_subject")]),
      .init(
        id: DimensionID("std.node.visibility"), name: "目标可用", description: "目标是否具有足够可见区域供当前配方判断",
        scope: .node, valueType: .boolean, valueSpace: .boolean,
        evaluatorIDs: [EvaluatorID("vision.local"), EvaluatorID("vision.saliency_subject")]),
      .init(
        id: DimensionID("std.node.visual_scale"), name: "视觉大小", description: "目标节点占画面的面积比例",
        scope: .node, valueType: .continuous,
        valueSpace: .continuous(min: 0, max: 1, unit: "frame_ratio"),
        evaluatorIDs: [EvaluatorID("vision.local"), EvaluatorID("vision.saliency_subject")]),
      .init(
        id: DimensionID("std.node.position_x"), name: "水平位置", description: "目标节点中心的水平位置",
        scope: .node, valueType: .continuous,
        valueSpace: .continuous(min: 0, max: 1, unit: "normalized_x"),
        evaluatorIDs: [EvaluatorID("vision.local"), EvaluatorID("vision.saliency_subject")]),
      .init(
        id: DimensionID("std.node.position_y"), name: "垂直位置", description: "目标节点中心的垂直位置",
        scope: .node, valueType: .continuous,
        valueSpace: .continuous(min: 0, max: 1, unit: "normalized_y"),
        evaluatorIDs: [EvaluatorID("vision.local"), EvaluatorID("vision.saliency_subject")]),
      .init(
        id: DimensionID("std.pose.body_orientation"), name: "身体朝向", description: "人物身体相对镜头的可见朝向",
        scope: .node, valueType: .ordinal, valueSpace: .ordinal(min: -2, max: 2),
        actionability: 0.85,
        evaluatorIDs: [EvaluatorID("vision.local"), EvaluatorID("djev.semantic")]),
      .init(
        id: DimensionID("std.relation.relative_scale"), name: "主体比例", description: "两个画面节点之间的相对视觉尺度",
        scope: .relation, valueType: .ordinal, valueSpace: .ordinal(min: -2, max: 2),
        actionability: 0.8,
        evaluatorIDs: [EvaluatorID("vision.saliency_relation"), EvaluatorID("djev.semantic")]),
      .init(
        id: DimensionID("std.relation.visual_balance"), name: "视觉平衡",
        description: "多个画面节点共同形成的视觉重心和平衡", scope: .relation, valueType: .ordinal,
        valueSpace: .ordinal(min: -2, max: 2),
        controlClass: .diagnostic, actionability: 0.55,
        evaluatorIDs: [EvaluatorID("vision.saliency_relation"), EvaluatorID("djev.semantic")]),
      .init(
        id: DimensionID("std.frame.luminance"), name: "整体亮度", description: "画面采样后的归一化平均亮度",
        scope: .frame, valueType: .continuous,
        valueSpace: .continuous(min: 0, max: 1, unit: "normalized_luma"),
        evaluatorIDs: [EvaluatorID("vision.frame")]),
      .init(
        id: DimensionID("std.frame.shadow_fraction"), name: "暗部比例", description: "画面中接近黑位的采样比例",
        scope: .frame, valueType: .continuous,
        valueSpace: .continuous(min: 0, max: 1, unit: "frame_ratio"),
        evaluatorIDs: [EvaluatorID("vision.frame")]),
      .init(
        id: DimensionID("std.frame.highlight_fraction"), name: "高光比例", description: "画面中接近高光溢出的采样比例",
        scope: .frame, valueType: .continuous,
        valueSpace: .continuous(min: 0, max: 1, unit: "frame_ratio"),
        evaluatorIDs: [EvaluatorID("vision.frame")]),
      .init(
        id: DimensionID("std.frame.detail_energy"), name: "细节能量", description: "画面局部边缘变化的轻量代理指标",
        scope: .frame, valueType: .continuous,
        valueSpace: .continuous(min: 0, max: 1, unit: "normalized_detail"),
        controlClass: .diagnostic, actionability: 0.35,
        evaluatorIDs: [EvaluatorID("vision.frame")]),
      .init(
        id: DimensionID("std.frame.saliency_x"), name: "视觉重心水平位置", description: "显著区域总体重心的水平位置",
        scope: .frame, valueType: .continuous,
        valueSpace: .continuous(min: 0, max: 1, unit: "normalized_x"),
        evaluatorIDs: [EvaluatorID("vision.frame")]),
      .init(
        id: DimensionID("std.frame.saliency_y"), name: "视觉重心垂直位置", description: "显著区域总体重心的垂直位置",
        scope: .frame, valueType: .continuous,
        valueSpace: .continuous(min: 0, max: 1, unit: "normalized_y"),
        evaluatorIDs: [EvaluatorID("vision.frame")]),
      .init(
        id: DimensionID("std.semantic.subject_presentation"), name: "主体呈现", description: "主体姿态、形态或摆放是否符合当前配方意图",
        scope: .node, valueType: .ordinal, valueSpace: .ordinal(min: -2, max: 2),
        actionability: 0.75,
        evaluatorIDs: [EvaluatorID("djev.semantic")]),
      .init(
        id: DimensionID("std.semantic.subject_background_separation"), name: "主体背景分离", description: "主体与背景在视觉上是否清晰分离",
        scope: .relation, valueType: .ordinal, valueSpace: .ordinal(min: -2, max: 2),
        actionability: 0.7,
        evaluatorIDs: [EvaluatorID("djev.semantic")]),
      .init(
        id: DimensionID("std.semantic.scene_depth"), name: "空间层次", description: "画面前中后景层次是否符合配方目标",
        scope: .frame, valueType: .ordinal, valueSpace: .ordinal(min: -2, max: 2),
        actionability: 0.55,
        evaluatorIDs: [EvaluatorID("djev.semantic")]),
      .init(
        id: DimensionID("std.semantic.color_harmony"), name: "色彩协调", description: "色彩关系与当前配方目标的匹配程度",
        scope: .frame, valueType: .ordinal, valueSpace: .ordinal(min: -2, max: 2),
        controlClass: .finalScore, actionability: 0.3,
        evaluatorIDs: [EvaluatorID("djev.semantic")]),
      .init(
        id: DimensionID("std.semantic.aesthetic_coherence"), name: "整体协调", description: "构图、主体和场景是否形成一致的视觉表达",
        scope: .frame, valueType: .ordinal, valueSpace: .ordinal(min: -2, max: 2),
        controlClass: .finalScore, actionability: 0.25,
        evaluatorIDs: [EvaluatorID("djev.semantic")]),
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
        id: EvaluatorID("vision.saliency_subject"),
        supportedDimensions: [
          DimensionID("std.node.exists"),
          DimensionID("std.node.visibility"),
          DimensionID("std.node.visual_scale"),
          DimensionID("std.node.position_x"),
          DimensionID("std.node.position_y"),
        ],
        kind: .localVision,
        latency: .fast,
        cost: .low,
        defaultReliability: 0.74
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
        id: EvaluatorID("vision.frame"),
        supportedDimensions: [
          DimensionID("std.frame.luminance"),
          DimensionID("std.frame.shadow_fraction"),
          DimensionID("std.frame.highlight_fraction"),
          DimensionID("std.frame.detail_energy"),
          DimensionID("std.frame.saliency_x"),
          DimensionID("std.frame.saliency_y"),
        ],
        kind: .localVision,
        latency: .realtime,
        cost: .veryLow,
        defaultReliability: 0.86
      ),
      .init(
        id: EvaluatorID("djev.semantic"),
        supportedDimensions: [
          DimensionID("std.pose.body_orientation"),
          DimensionID("std.relation.relative_scale"),
          DimensionID("std.relation.visual_balance"),
          DimensionID("std.semantic.subject_presentation"),
          DimensionID("std.semantic.subject_background_separation"),
          DimensionID("std.semantic.scene_depth"),
          DimensionID("std.semantic.color_harmony"),
          DimensionID("std.semantic.aesthetic_coherence"),
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
