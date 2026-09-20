import Foundation
import GuidanceCore

public struct RecipeNodeDTO: Codable, Sendable { public let id: String; public let type: String; public let semantic_class: String; public let role: String; public let presence: String }
public struct RecipeTargetDTO: Codable, Sendable {
    public let type: String
    public let value: Bool?
    public let idealRange: [Double]?
    public let idealLabel: String?
    public let acceptable: [Double]?

    private enum CodingKeys: String, CodingKey {
        case type
        case value
        case ideal
        case acceptable
    }

    public init(
        type: String,
        value: Bool? = nil,
        idealRange: [Double]? = nil,
        idealLabel: String? = nil,
        acceptable: [Double]? = nil
    ) {
        self.type = type
        self.value = value
        self.idealRange = idealRange
        self.idealLabel = idealLabel
        self.acceptable = acceptable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        value = try container.decodeIfPresent(Bool.self, forKey: .value)
        idealRange = try? container.decode([Double].self, forKey: .ideal)
        idealLabel = try? container.decode(String.self, forKey: .ideal)
        acceptable = try container.decodeIfPresent([Double].self, forKey: .acceptable)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(value, forKey: .value)
        if let idealRange {
            try container.encode(idealRange, forKey: .ideal)
        } else {
            try container.encodeIfPresent(idealLabel, forKey: .ideal)
        }
        try container.encodeIfPresent(acceptable, forKey: .acceptable)
    }
}
public struct RecipeGoalDTO: Codable, Sendable { public let id: String; public let dimension: String; public let bind: String; public let target: RecipeTargetDTO; public let `class`: String; public let importance: Double }
public struct RecipePolicyDTO: Codable, Sendable { public let allow_goal_skip: Bool; public let allow_goal_lock: Bool; public let allow_variant_switch: Bool }
public struct RecipeDTO: Codable, Sendable { public let kind: String; public let id: String; public let version: String; public let nodes: [RecipeNodeDTO]; public let goals: [RecipeGoalDTO]; public let author_policy: RecipePolicyDTO }

public struct CompiledRecipe: Sendable {
    public let source: RecipeDTO
    public let dimensions: Set<DimensionID>
    public let goals: [GoalDefinition]
    public let actions: [ActionDefinition]
    public let validationIssues: [ValidationIssue]
    public var isValid: Bool { validationIssues.isEmpty }
}

private final class RecipeBundleMarker {}

public struct RecipeLoader: Sendable {
    public init() {}

    public func loadEnvironmentalPortrait() -> CompiledRecipe {
        let data = Bundle(for: RecipeBundleMarker.self).url(forResource: "environment_portrait.recipe", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        if let data, let dto = try? JSONDecoder().decode(RecipeDTO.self, from: data) { return compile(dto) }
        return compile(Self.fallbackDTO)
    }

    public func compile(_ dto: RecipeDTO) -> CompiledRecipe {
        let dimensions = Set(dto.goals.map { DimensionID($0.dimension) })
        let goals = dto.goals.map { goal in
            GoalDefinition(id: GoalID(goal.id), dimension: DimensionID(goal.dimension), binding: Binding(bindingNodes(goal.bind)), target: makeTarget(goal.target), constraint: makeConstraint(goal.class), importance: goal.importance)
        }
        let goalByDimension = Dictionary(uniqueKeysWithValues: goals.map { ($0.dimension.rawValue, $0.id) })
        let actions = goals.flatMap { goal in
            let gain = max(0.1, goal.importance)
            let possibleDamage = Set(damagedDimensions(for: goal.dimension.rawValue).compactMap { goalByDimension[$0] })
            return [
                ActionDefinition(
                    id: ActionID("guide.\(goal.id.rawValue).primary"),
                    affects: [goal.id],
                    damages: possibleDamage,
                    expectedGain: gain,
                    burden: 0.08,
                    risk: possibleDamage.isEmpty ? 0 : 0.04,
                    family: "\(goal.dimension.rawValue).primary"
                ),
                ActionDefinition(
                    id: ActionID("guide.\(goal.id.rawValue).alternative"),
                    affects: [goal.id],
                    expectedGain: gain * 0.82,
                    burden: 0.04,
                    uncertainty: 0.04,
                    family: "\(goal.dimension.rawValue).alternative"
                ),
            ]
        }
        let issues = RecipeValidator().validate(goals: goals, dimensions: dimensions, actions: actions, cancellationAllowed: true)
        return CompiledRecipe(source: dto, dimensions: dimensions, goals: goals, actions: actions, validationIssues: issues)
    }

    private func bindingNodes(_ bind: String) -> [NodeID] {
        bind.split(separator: "_").map { NodeID(String($0)) }
    }

    private func makeTarget(_ target: RecipeTargetDTO) -> GoalTarget {
        switch target.type {
        case "BOOLEAN": return .boolean(target.value ?? true)
        case "RANGE":
            let ideal = target.idealRange ?? [0, 1], acceptable = target.acceptable ?? ideal
            return .band(TargetBand(ideal: ideal[0]...ideal[1], acceptable: acceptable[0]...acceptable[1]))
        case "ORDINAL":
            return .ordinal(ordinalValue(for: target.idealLabel))
        default:
            return .categorical(target.idealLabel ?? "MATCH")
        }
    }

    private func ordinalValue(for label: String?) -> Int {
        switch label?.uppercased() {
        case "BELOW": -2
        case "SLIGHTLY_BELOW": -1
        case "MATCH": 0
        case "SLIGHTLY_ABOVE": 1
        case "ABOVE": 2
        default: 0
        }
    }

    private func makeConstraint(_ value: String) -> ConstraintClass {
        switch value.uppercased() { case "HARD": .hard; case "SOFT": .soft; default: .core }
    }

    private func damagedDimensions(for dimension: String) -> [String] {
        switch dimension {
        case "std.node.visibility":
            ["std.node.visual_scale"]
        case "std.node.visual_scale":
            ["std.node.visibility", "std.relation.relative_scale"]
        case "std.node.position_x":
            ["std.relation.visual_balance"]
        case "std.node.position_y":
            ["std.node.visibility"]
        case "std.pose.body_orientation":
            ["std.node.visual_scale"]
        case "std.relation.relative_scale":
            ["std.node.visual_scale", "std.node.position_x"]
        case "std.relation.visual_balance":
            ["std.node.position_x"]
        default:
            []
        }
    }

    private static let fallbackDTO = RecipeDTO(
        kind: "Recipe", id: "fallback.environment_portrait", version: "0.1.0",
        nodes: [
            RecipeNodeDTO(id: "primary", type: "ENTITY", semantic_class: "person", role: "PRIMARY_SUBJECT", presence: "REQUIRED"),
            RecipeNodeDTO(id: "anchor", type: "REGION", semantic_class: "scenic_anchor", role: "SCENE_ANCHOR", presence: "REQUIRED"),
        ],
        goals: [
            RecipeGoalDTO(id: "person_exists", dimension: "std.node.exists", bind: "primary", target: RecipeTargetDTO(type: "BOOLEAN", value: true), class: "HARD", importance: 1),
            RecipeGoalDTO(id: "person_visibility", dimension: "std.node.visibility", bind: "primary", target: RecipeTargetDTO(type: "BOOLEAN", value: true), class: "HARD", importance: 1),
            RecipeGoalDTO(id: "person_scale", dimension: "std.node.visual_scale", bind: "primary", target: RecipeTargetDTO(type: "RANGE", idealRange: [0.16, 0.24], acceptable: [0.12, 0.30]), class: "CORE", importance: 0.9),
            RecipeGoalDTO(id: "person_x", dimension: "std.node.position_x", bind: "primary", target: RecipeTargetDTO(type: "RANGE", idealRange: [0.58, 0.72], acceptable: [0.52, 0.78]), class: "CORE", importance: 0.8),
            RecipeGoalDTO(id: "person_y", dimension: "std.node.position_y", bind: "primary", target: RecipeTargetDTO(type: "RANGE", idealRange: [0.42, 0.58], acceptable: [0.34, 0.66]), class: "CORE", importance: 0.72),
            RecipeGoalDTO(id: "body_orientation", dimension: "std.pose.body_orientation", bind: "primary", target: RecipeTargetDTO(type: "ORDINAL", idealLabel: "MATCH"), class: "CORE", importance: 0.75),
            RecipeGoalDTO(id: "relative_scale", dimension: "std.relation.relative_scale", bind: "primary_anchor", target: RecipeTargetDTO(type: "ORDINAL", idealLabel: "MATCH"), class: "CORE", importance: 0.92),
            RecipeGoalDTO(id: "anchor_balance", dimension: "std.relation.visual_balance", bind: "primary_anchor", target: RecipeTargetDTO(type: "ORDINAL", idealLabel: "MATCH"), class: "SOFT", importance: 0.6),
        ],
        author_policy: RecipePolicyDTO(allow_goal_skip: true, allow_goal_lock: true, allow_variant_switch: true)
    )
}
