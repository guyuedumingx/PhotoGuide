import Foundation
import GuidanceCore

public struct RecipeNodeDTO: Codable, Sendable {
  public let id: String
  public let type: String
  public let semanticClass: String?
  public let roles: [String]
  public let presence: String
}

public struct RecipeParticipantDTO: Codable, Sendable {
  public let role: String
  public let node: String
}
public struct RecipeRelationDTO: Codable, Sendable {
  public let id: String
  public let type: String
  public let directed: Bool
  public let participants: [RecipeParticipantDTO]
}
public struct RecipeBindingDTO: Codable, Sendable {
  public let scope: String
  public let id: String?
}

public struct RecipeTargetDTO: Codable, Sendable {
  public let type: String
  public let value: Bool?
  public let idealRange: [Double]?
  public let idealOrdinal: Int?
  public let idealLabel: String?
  public let acceptable: [Double]?

  public init(
    type: String,
    value: Bool? = nil,
    idealRange: [Double]? = nil,
    idealOrdinal: Int? = nil,
    idealLabel: String? = nil,
    acceptable: [Double]? = nil
  ) {
    self.type = type
    self.value = value
    self.idealRange = idealRange
    self.idealOrdinal = idealOrdinal
    self.idealLabel = idealLabel
    self.acceptable = acceptable
  }

  private enum CodingKeys: String, CodingKey { case type, value, ideal, acceptable }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try container.decode(String.self, forKey: .type)
    value = try container.decodeIfPresent(Bool.self, forKey: .value)
    idealRange = try? container.decode([Double].self, forKey: .ideal)
    idealOrdinal = try? container.decode(Int.self, forKey: .ideal)
    idealLabel = try? container.decode(String.self, forKey: .ideal)
    acceptable = try container.decodeIfPresent([Double].self, forKey: .acceptable)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encodeIfPresent(value, forKey: .value)
    if let idealRange {
      try container.encode(idealRange, forKey: .ideal)
    } else if let idealOrdinal {
      try container.encode(idealOrdinal, forKey: .ideal)
    } else {
      try container.encodeIfPresent(idealLabel, forKey: .ideal)
    }
    try container.encodeIfPresent(acceptable, forKey: .acceptable)
  }
}

public struct RecipeGoalDTO: Codable, Sendable {
  public let id: String
  public let dimension: String
  public let binding: RecipeBindingDTO
  public let target: RecipeTargetDTO
  public let `class`: String
  public let importance: Double
  public let dependencies: [String]?
}

public struct RecipeEffectDTO: Codable, Sendable {
  public let goal: String
  public let gain: Double
  public let damage: Double?
}

public struct RecipeInformationEffectDTO: Codable, Sendable {
  public let goal: String
  public let confidenceGain: Double
  public let resolutionProbability: Double?
}

public struct RecipeActionConditionDTO: Codable, Sendable {
  public let type: String
  public let goal: String?
  public let number: Double?
  public let ordinal: Int?
  public let bool: Bool?
}

public struct RecipeActionDTO: Codable, Sendable {
  public let id: String
  public let actor: String
  public let operation: String
  public let direction: String
  public let magnitude: String
  public let coordinateFrame: String
  public let condition: RecipeActionConditionDTO
  public let effects: [RecipeEffectDTO]
  public let informationEffects: [RecipeInformationEffectDTO]?
  public let burden: Double?
  public let risk: Double?
  public let uncertainty: Double?
  public let family: String
  public let requiredCapability: String?
  public let safety: String
  public let presentationKey: String
}

public struct RecipePolicyDTO: Codable, Sendable {
  public let allowGoalSkip: Bool
  public let allowGoalLock: Bool
  public let allowVariantSwitch: Bool

  public init(
    allowGoalSkip: Bool = false,
    allowGoalLock: Bool = true,
    allowVariantSwitch: Bool = false
  ) {
    self.allowGoalSkip = allowGoalSkip
    self.allowGoalLock = allowGoalLock
    self.allowVariantSwitch = allowVariantSwitch
  }
}


public enum RecipeDomain: String, Codable, CaseIterable, Sendable {
  case portrait
  case travel
  case food
  case nature
  case product
  case pet
  case architecture
  case landscape
  case general
}

public enum RecipeSubjectStrategy: String, Codable, Sendable {
  case human
  case saliency
  case scene
}

public enum RecipeAnchorStrategy: String, Codable, Sendable {
  case none
  case automatic
  case optional
  case required
}

/// Declarative perception contract owned by the Recipe rather than the UI.
/// New Recipe families can therefore choose how a primary subject is acquired
/// without adding subject-specific branches to the control kernel.
public struct RecipePerceptionDTO: Codable, Sendable {
  public let subjectStrategy: RecipeSubjectStrategy
  public let semanticHint: String?
  public let faceAssist: Bool?
  public let poseAssist: Bool?
  public let anchorStrategy: RecipeAnchorStrategy?
  public let allowsManualSubjectSelection: Bool?

  public init(
    subjectStrategy: RecipeSubjectStrategy,
    semanticHint: String? = nil,
    faceAssist: Bool? = nil,
    poseAssist: Bool? = nil,
    anchorStrategy: RecipeAnchorStrategy? = nil,
    allowsManualSubjectSelection: Bool? = nil
  ) {
    self.subjectStrategy = subjectStrategy
    self.semanticHint = semanticHint
    self.faceAssist = faceAssist
    self.poseAssist = poseAssist
    self.anchorStrategy = anchorStrategy
    self.allowsManualSubjectSelection = allowsManualSubjectSelection
  }
}


public struct RecipeCriticDimensionDTO: Codable, Sendable {
  public let id: String
  public let name: String
  public let rubric: String
  public let weight: Double
  public let targetScore: Double
  public let actionability: Double
  public let requiredForReady: Bool?
  public let minimumConfidence: Double?

  public init(
    id: String,
    name: String,
    rubric: String,
    weight: Double,
    targetScore: Double = 0.78,
    actionability: Double = 0.8,
    requiredForReady: Bool? = false,
    minimumConfidence: Double? = 0.45
  ) {
    self.id = id
    self.name = name
    self.rubric = rubric
    self.weight = weight
    self.targetScore = targetScore
    self.actionability = actionability
    self.requiredForReady = requiredForReady
    self.minimumConfidence = minimumConfidence
  }
}

public struct RecipeCriticDTO: Codable, Sendable {
  public let intent: String
  public let adviceStyle: String?
  public let preferredSampleCount: Int?
  public let minimumSampleSpacing: Double?
  public let dimensions: [RecipeCriticDimensionDTO]

  public init(
    intent: String,
    adviceStyle: String? = nil,
    preferredSampleCount: Int? = 3,
    minimumSampleSpacing: Double? = 0.22,
    dimensions: [RecipeCriticDimensionDTO]
  ) {
    self.intent = intent
    self.adviceStyle = adviceStyle
    self.preferredSampleCount = preferredSampleCount
    self.minimumSampleSpacing = minimumSampleSpacing
    self.dimensions = dimensions
  }
}

public struct RecipePresentationDTO: Codable, Sendable {
  public let domain: RecipeDomain
  public let icon: String
  public let tags: [String]
  public let featuredRank: Int?

  public init(domain: RecipeDomain, icon: String, tags: [String], featuredRank: Int? = nil) {
    self.domain = domain
    self.icon = icon
    self.tags = tags
    self.featuredRank = featuredRank
  }
}

public struct RecipeDTO: Codable, Sendable {
  public let kind: String
  public let id: String
  public let version: String
  public let title: String
  public let subtitle: String
  public let nodes: [RecipeNodeDTO]
  public let relations: [RecipeRelationDTO]
  public let goals: [RecipeGoalDTO]
  public let actions: [RecipeActionDTO]
  public let authorPolicy: RecipePolicyDTO
  public let perception: RecipePerceptionDTO?
  public let presentation: RecipePresentationDTO?
  public let references: [RecipeReferenceDTO]?
  public let questions: [RecipeQuestionDTO]?
  public let critic: RecipeCriticDTO?

  public init(
    kind: String = "Recipe",
    id: String,
    version: String = "1",
    title: String,
    subtitle: String,
    nodes: [RecipeNodeDTO] = [],
    relations: [RecipeRelationDTO] = [],
    goals: [RecipeGoalDTO] = [],
    actions: [RecipeActionDTO] = [],
    authorPolicy: RecipePolicyDTO = .init(),
    perception: RecipePerceptionDTO? = .init(
      subjectStrategy: .scene,
      anchorStrategy: RecipeAnchorStrategy.none,
      allowsManualSubjectSelection: false),
    presentation: RecipePresentationDTO? = .init(
      domain: .general, icon: "viewfinder", tags: []),
    references: [RecipeReferenceDTO]? = nil,
    questions: [RecipeQuestionDTO]? = nil,
    critic: RecipeCriticDTO? = nil
  ) {
    self.kind = kind
    self.id = id
    self.version = version
    self.title = title
    self.subtitle = subtitle
    self.nodes = nodes
    self.relations = relations
    self.goals = goals
    self.actions = actions
    self.authorPolicy = authorPolicy
    self.perception = perception
    self.presentation = presentation
    self.references = references
    self.questions = questions
    self.critic = critic
  }
}


public extension RecipeDTO {
  var primarySubjectNode: RecipeNodeDTO? {
    nodes.first { $0.roles.contains("PRIMARY_SUBJECT") }
  }

  var resolvedPerception: RecipePerceptionDTO {
    if let perception { return perception }
    let semantic = primarySubjectNode?.semanticClass?.lowercased()
    let isHuman = semantic == "person" || semantic == "human"
    return RecipePerceptionDTO(
      subjectStrategy: isHuman ? .human : (primarySubjectNode == nil ? .scene : .saliency),
      semanticHint: primarySubjectNode?.semanticClass,
      faceAssist: isHuman,
      poseAssist: isHuman,
      anchorStrategy: relations.isEmpty ? RecipeAnchorStrategy.none : .automatic,
      allowsManualSubjectSelection: !isHuman)
  }

  var resolvedCritic: CriticProfile {
    if let critic {
      return CriticProfile(
        intent: critic.intent,
        dimensions: critic.dimensions.map { item in
          CriticDimensionSpec(
            id: item.id, name: item.name, rubric: item.rubric, weight: item.weight,
            targetScore: item.targetScore, actionability: item.actionability,
            requiredForReady: item.requiredForReady ?? false,
            minimumConfidence: item.minimumConfidence ?? 0.45)
        },
        adviceStyle: critic.adviceStyle
          ?? "Give one concrete, high-impact photography adjustment at a time.",
        preferredSampleCount: critic.preferredSampleCount ?? 3,
        minimumSampleSpacing: critic.minimumSampleSpacing ?? 0.22)
    }

    // Backward-compatible fallback for third-party Recipes. Shipping Recipes
    // declare an explicit critic profile in JSON so the multimodal model, not
    // local subject heuristics, defines the product's photographic judgment.
    return CriticProfile(
      intent: "Evaluate the current photograph for the Recipe intent: \(title). \(subtitle)",
      dimensions: [
        .init(
          id: "composition", name: "Composition",
          rubric: "Judge framing, visual balance, spacing, hierarchy and edge tension.",
          weight: 1, targetScore: 0.80, actionability: 1),
        .init(
          id: "lighting", name: "Lighting",
          rubric: "Judge exposure, direction, contrast, highlight and shadow handling for the intended image.",
          weight: 0.85, targetScore: 0.78, actionability: 0.8),
        .init(
          id: "subject", name: "Subject presentation",
          rubric: "Judge how clearly and intentionally the important visual subject or scene is presented.",
          weight: 0.9, targetScore: 0.78, actionability: 0.9),
        .init(
          id: "color", name: "Color",
          rubric: "Judge color harmony, white balance and whether color supports the intended mood.",
          weight: 0.55, targetScore: 0.72, actionability: 0.45),
        .init(
          id: "overall", name: "Overall image quality",
          rubric: "Judge whether the image already feels deliberate, coherent and professionally photographable.",
          weight: 0.8, targetScore: 0.78, actionability: 0.35),
      ])
  }

  var resolvedPresentation: RecipePresentationDTO {
    if let presentation { return presentation }
    let isHuman = resolvedPerception.subjectStrategy == .human
    return RecipePresentationDTO(
      domain: isHuman ? .portrait : .general,
      icon: isHuman ? "person.crop.rectangle" : "viewfinder",
      tags: [])
  }
}

public enum RecipeFactory {
  /// A model-first Recipe contains only the photographic intent and critic rubric.
  /// Local goals/actions are optional assistive layers and are intentionally omitted here.
  public static func criticOnly(
    id: String,
    title: String,
    subtitle: String,
    intent: String,
    domain: RecipeDomain = .general,
    icon: String = "viewfinder",
    tags: [String] = [],
    dimensions: [RecipeCriticDimensionDTO]? = nil
  ) -> RecipeDTO {
    let cleanID = id.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedDimensions = dimensions?.isEmpty == false ? dimensions! : defaultDimensions
    return RecipeDTO(
      id: cleanID.isEmpty ? "user.\(UUID().uuidString.lowercased())" : cleanID,
      title: title,
      subtitle: subtitle,
      perception: .init(
        subjectStrategy: .scene,
        anchorStrategy: RecipeAnchorStrategy.none,
        allowsManualSubjectSelection: false),
      presentation: .init(domain: domain, icon: icon, tags: tags),
      critic: .init(
        intent: intent,
        adviceStyle: "Give one short, concrete, high-impact adjustment that can be acted on while the camera remains open.",
        preferredSampleCount: 3,
        minimumSampleSpacing: 0.22,
        dimensions: resolvedDimensions))
  }

  public static var defaultDimensions: [RecipeCriticDimensionDTO] {
    [
      .init(
        id: "composition", name: "Composition",
        rubric: "Judge framing, balance, hierarchy, spacing, edge tension and use of negative space.",
        weight: 1.0, targetScore: 0.80, actionability: 1.0, requiredForReady: true),
      .init(
        id: "lighting", name: "Lighting",
        rubric: "Judge exposure, highlight control, shadow detail, direction and quality of light for the intended image.",
        weight: 0.92, targetScore: 0.78, actionability: 0.9, requiredForReady: true),
      .init(
        id: "subject", name: "Subject",
        rubric: "Judge whether the important visual subject or scene reads clearly and intentionally.",
        weight: 0.9, targetScore: 0.78, actionability: 0.9),
      .init(
        id: "timing", name: "Timing",
        rubric: "Judge transient expression, gesture, motion phase, stability and whether this is the right instant to capture.",
        weight: 0.82, targetScore: 0.76, actionability: 0.85),
      .init(
        id: "color", name: "Color",
        rubric: "Judge white balance, color harmony and whether color supports the intended mood.",
        weight: 0.58, targetScore: 0.72, actionability: 0.45),
      .init(
        id: "overall", name: "Overall",
        rubric: "Judge whether the live frame feels deliberate, coherent and photographically strong for the Recipe intent.",
        weight: 0.8, targetScore: 0.78, actionability: 0.5),
    ]
  }
}

public struct CompiledRecipe: Sendable {
  public let source: RecipeDTO
  public let registry: GuidanceRegistry
  public let goals: [GoalDefinition]
  public let actions: [ActionDefinition]
  public let validationIssues: [ValidationIssue]

  public var isValid: Bool { !validationIssues.contains { $0.severity == .error } }
}

private final class RecipeBundleMarker {}

public enum RecipePreset: String, CaseIterable, Codable, Sendable {
  case environmentPortrait = "environment_portrait"
  case soloPortrait = "solo_portrait"
  case centeredPortrait = "centered_portrait"
  case closeupPortrait = "closeup_portrait"
  case travelPortrait = "travel_portrait"
  case food = "food"
  case flowerMacro = "flower_macro"
  case landscape = "landscape"
  case product = "product"
  case pet = "pet"
  case architecture = "architecture"

  public var requiresSceneAnchor: Bool {
    switch self {
    case .environmentPortrait, .travelPortrait: true
    default: false
    }
  }
}

public struct RecipeLoader: Sendable {
  public init() {}

  public func loadEnvironmentalPortrait() -> CompiledRecipe {
    load(.environmentPortrait)
  }

  public func catalog() -> [CompiledRecipe] {
    RecipePreset.allCases.map(load)
  }

  public func load(_ preset: RecipePreset) -> CompiledRecipe {
    #if SWIFT_PACKAGE
      let resourceBundle = Bundle.module
    #else
      let resourceBundle = Bundle(for: RecipeBundleMarker.self)
    #endif
    guard
      let url = resourceBundle.url(forResource: "\(preset.rawValue).recipe", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let dto = try? JSONDecoder().decode(RecipeDTO.self, from: data)
    else {
      return Self.emergencyRecipe()
    }
    return compile(dto)
  }

  public func compile(_ dto: RecipeDTO) -> CompiledRecipe {
    let nodes = dto.nodes.map(compileNode)
    let relations = dto.relations.map(compileRelation)
    let standard = GuidanceRegistry.standardPhotography
    let registry = GuidanceRegistry(
      nodes: nodes,
      relations: relations,
      dimensions: Array(standard.dimensions.values),
      evaluators: Array(standard.evaluators.values)
    )
    let goals = dto.goals.map(compileGoal)
    let actions = dto.actions.map(compileAction)
    let issues =
      preflightIssues(dto)
      + RecipeValidator().validate(
        goals: goals, actions: actions, registry: registry, cancellationAllowed: true)
    return CompiledRecipe(
      source: dto, registry: registry, goals: goals, actions: actions, validationIssues: issues)
  }

  private func compileNode(_ dto: RecipeNodeDTO) -> NodeDefinition {
    NodeDefinition(
      id: NodeID(dto.id),
      type: nodeType(dto.type),
      semanticClass: dto.semanticClass,
      roles: Set(dto.roles),
      presence: presence(dto.presence)
    )
  }

  private func compileRelation(_ dto: RecipeRelationDTO) -> RelationDefinition {
    RelationDefinition(
      id: RelationID(dto.id),
      type: dto.type,
      participants: dto.participants.map { .init(role: $0.role, node: NodeID($0.node)) },
      directed: dto.directed
    )
  }

  private func compileGoal(_ dto: RecipeGoalDTO) -> GoalDefinition {
    GoalDefinition(
      id: GoalID(dto.id),
      dimension: DimensionID(dto.dimension),
      binding: binding(dto.binding),
      target: target(dto.target),
      constraint: constraint(dto.class),
      importance: dto.importance,
      dependencies: Set((dto.dependencies ?? []).map(GoalID.init)),
      stability: .init(
        enterThreshold: dto.class.uppercased() == "HARD" ? 0.90 : 0.80,
        exitThreshold: dto.class.uppercased() == "HARD" ? 0.72 : 0.62)
    )
  }

  private func compileAction(_ dto: RecipeActionDTO) -> ActionDefinition {
    ActionDefinition(
      id: ActionID(dto.id),
      actor: actor(dto.actor),
      operation: operation(dto.operation),
      direction: direction(dto.direction),
      magnitude: magnitude(dto.magnitude),
      coordinateFrame: coordinateFrame(dto.coordinateFrame),
      condition: condition(dto.condition),
      effects: dto.effects.map {
        .init(goal: GoalID($0.goal), expectedImprovement: $0.gain, possibleDamage: $0.damage ?? 0)
      },
      informationEffects: (dto.informationEffects ?? []).map {
        .init(
          goal: GoalID($0.goal),
          confidenceGain: $0.confidenceGain,
          resolutionProbability: $0.resolutionProbability ?? 1
        )
      },
      burden: dto.burden ?? 0,
      risk: dto.risk ?? 0,
      uncertainty: dto.uncertainty ?? 0,
      family: dto.family,
      requiredCapability: dto.requiredCapability,
      safety: safety(dto.safety),
      presentationKey: dto.presentationKey
    )
  }

  private func binding(_ dto: RecipeBindingDTO) -> Binding {
    switch dto.scope.uppercased() {
    case "NODE": return .node(NodeID(dto.id ?? ""))
    case "RELATION": return .relation(RelationID(dto.id ?? ""))
    case "CAPTURE": return .capture
    default: return .frame
    }
  }

  private func target(_ dto: RecipeTargetDTO) -> GoalTarget {
    switch dto.type.uppercased() {
    case "BOOLEAN": return .boolean(dto.value ?? true)
    case "RANGE":
      guard let ideal = validPair(dto.idealRange) else {
        return .band(.init(ideal: 0...0, acceptable: 0...0))
      }
      let acceptable = validPair(dto.acceptable) ?? ideal
      guard acceptable[0] <= ideal[0], ideal[1] <= acceptable[1] else {
        return .band(.init(ideal: ideal[0]...ideal[1], acceptable: ideal[0]...ideal[1]))
      }
      return .band(.init(ideal: ideal[0]...ideal[1], acceptable: acceptable[0]...acceptable[1]))
    case "ORDINAL": return .ordinal(dto.idealOrdinal ?? ordinalLabel(dto.idealLabel))
    default: return .categorical(dto.idealLabel ?? "MATCH")
    }
  }

  private func validPair(_ values: [Double]?) -> [Double]? {
    guard let values, values.count == 2,
      values[0].isFinite, values[1].isFinite,
      values[0] <= values[1]
    else { return nil }
    return values
  }

  private func preflightIssues(_ dto: RecipeDTO) -> [ValidationIssue] {
    var issues = [ValidationIssue]()
    let perception = dto.resolvedPerception
    let primary = dto.primarySubjectNode
    if perception.subjectStrategy != .scene && primary == nil {
      issues.append(.init(
        rule: .invalidPerceptionProfile, severity: .error,
        message: "\(dto.id): non-scene perception requires PRIMARY_SUBJECT"))
    }
    if perception.subjectStrategy == .human {
      let semantic = primary?.semanticClass?.lowercased()
      if semantic != "person" && semantic != "human" {
        issues.append(.init(
          rule: .invalidPerceptionProfile, severity: .error,
          message: "\(dto.id): human strategy requires person semanticClass"))
      }
    }
    if perception.subjectStrategy == .scene,
      dto.goals.contains(where: { $0.binding.scope.uppercased() == "NODE" && $0.class.uppercased() == "HARD" })
    {
      issues.append(.init(
        rule: .perceptionCoverageGap, severity: .error,
        message: "\(dto.id): scene-only strategy cannot satisfy HARD node goals"))
    }
    for goal in dto.goals {
      if !goal.importance.isFinite || !(0...1).contains(goal.importance) {
        issues.append(.init(rule: .invalidGoalImportance, severity: .error, message: goal.id))
      }
      if goal.target.type.uppercased() == "RANGE" {
        guard let ideal = validPair(goal.target.idealRange),
          let acceptable = validPair(goal.target.acceptable ?? goal.target.idealRange),
          acceptable[0] <= ideal[0], ideal[1] <= acceptable[1]
        else {
          issues.append(.init(rule: .invalidTargetRange, severity: .error, message: goal.id))
          continue
        }
      }
    }

    for action in dto.actions {
      let costs: [Double] = [
        action.burden ?? 0.0, action.risk ?? 0.0, action.uncertainty ?? 0.0,
      ]
      let effects: [Double] = action.effects.flatMap { effect -> [Double] in
        [effect.gain, effect.damage ?? 0.0]
      }
      let informationEffects: [Double] = (action.informationEffects ?? []).flatMap {
        effect -> [Double] in
        [effect.confidenceGain, effect.resolutionProbability ?? 1.0]
      }
      if (costs + effects + informationEffects).contains(where: {
        !$0.isFinite || !(0...1).contains($0)
      }) {
        issues.append(.init(rule: .invalidActionNumeric, severity: .error, message: action.id))
      }
      if let number = action.condition.number, !number.isFinite {
        issues.append(.init(rule: .invalidActionNumeric, severity: .error, message: action.id))
      }
      if action.family.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || action.presentationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        issues.append(.init(rule: .invalidActionMetadata, severity: .error, message: action.id))
      }
    }
    return issues
  }

  private func condition(_ dto: RecipeActionConditionDTO) -> ActionCondition {
    let goal = GoalID(dto.goal ?? "")
    switch dto.type.uppercased() {
    case "GOAL_UNSATISFIED": return .goalUnsatisfied(goal)
    case "CONTINUOUS_BELOW": return .continuousBelow(goal, dto.number ?? 0)
    case "CONTINUOUS_ABOVE": return .continuousAbove(goal, dto.number ?? 0)
    case "ORDINAL_BELOW": return .ordinalBelow(goal, dto.ordinal ?? 0)
    case "ORDINAL_ABOVE": return .ordinalAbove(goal, dto.ordinal ?? 0)
    case "BOOLEAN_EQUALS": return .booleanEquals(goal, dto.bool ?? false)
    default: return .always
    }
  }

  private func nodeType(_ value: String) -> NodeType {
    switch value.uppercased() {
    case "ENTITY_GROUP": .entityGroup
    case "REGION": .region
    case "SURFACE": .surface
    case "TEXT": .text
    case "GEOMETRY": .geometry
    case "LIGHT_SOURCE": .lightSource
    default: .entity
    }
  }

  private func presence(_ value: String) -> PresencePolicy {
    switch value.uppercased() {
    case "REQUIRED": .required
    case "SUBSTITUTABLE": .substitutable
    case "IGNORE": .ignore
    default: .optional
    }
  }
  private func constraint(_ value: String) -> ConstraintClass {
    switch value.uppercased() {
    case "HARD": .hard
    case "SOFT": .soft
    default: .core
    }
  }
  private func actor(_ value: String) -> ActionActor {
    switch value.uppercased() {
    case "PHOTOGRAPHER": .photographer
    case "CAMERA": .camera
    case "SCENE_OBJECT": .sceneObject
    case "LIGHT": .light
    case "SYSTEM": .system
    default: .subject
    }
  }
  private func operation(_ value: String) -> ActionOperation {
    switch value.uppercased() {
    case "ROTATE": .rotate
    case "ZOOM": .zoom
    case "REFRAME": .reframe
    case "HOLD": .hold
    case "WAIT": .wait
    case "CAPTURE": .capture
    case "SELECT_ANCHOR": .selectAnchor
    case "SELECT_SUBJECT": .selectSubject
    case "ADJUST_EXPOSURE": .adjustExposure
    default: .move
    }
  }
  private func direction(_ value: String) -> ActionDirection {
    switch value.uppercased() {
    case "LEFT": .left
    case "RIGHT": .right
    case "UP": .up
    case "DOWN": .down
    case "FORWARD": .forward
    case "BACKWARD": .backward
    case "TOWARD_CAMERA": .towardCamera
    case "AWAY_FROM_CAMERA": .awayFromCamera
    default: .none
    }
  }
  private func magnitude(_ value: String) -> ActionMagnitude {
    switch value.uppercased() {
    case "TINY": .tiny
    case "MEDIUM": .medium
    case "LARGE": .large
    default: .small
    }
  }
  private func coordinateFrame(_ value: String) -> CoordinateFrame {
    switch value.uppercased() {
    case "PHOTOGRAPHER_SPACE": .photographerSpace
    case "SUBJECT_SPACE": .subjectSpace
    case "DEVICE_SPACE": .deviceSpace
    case "WORLD_SPACE": .worldSpace
    default: .imageSpace
    }
  }
  private func safety(_ value: String) -> ActionSafetyClass {
    switch value.uppercased() {
    case "CONTEXT_DEPENDENT": .contextDependent
    case "RESTRICTED": .restricted
    default: .safe
    }
  }
  private func ordinalLabel(_ value: String?) -> Int {
    switch value?.uppercased() {
    case "BELOW": -2
    case "SLIGHTLY_BELOW": -1
    case "SLIGHTLY_ABOVE": 1
    case "ABOVE": 2
    default: 0
    }
  }

  private static func emergencyRecipe() -> CompiledRecipe {
    let standard = GuidanceRegistry.standardPhotography
    let primary = NodeDefinition(
      id: NodeID("primary"), type: .entity, semanticClass: nil,
      roles: ["PRIMARY_SUBJECT"], presence: .required)
    let registry = GuidanceRegistry(
      nodes: [primary],
      dimensions: Array(standard.dimensions.values),
      evaluators: Array(standard.evaluators.values)
    )
    let goal = GoalDefinition(
      id: GoalID("subject_exists"),
      dimension: DimensionID("std.node.exists"),
      binding: .node(NodeID("primary")),
      target: .boolean(true),
      constraint: .hard
    )
    let action = ActionDefinition(
      id: ActionID("subject.enter_frame"),
      actor: .subject,
      operation: .move,
      effects: [.init(goal: goal.id, expectedImprovement: 1)],
      family: "subject.enter",
      presentationKey: "subject.enter_frame"
    )
    let node = RecipeNodeDTO(
      id: "primary", type: "ENTITY", semanticClass: nil, roles: ["PRIMARY_SUBJECT"],
      presence: "REQUIRED")
    let target = RecipeTargetDTO(type: "BOOLEAN", value: true)
    let dto = RecipeDTO(
      kind: "Recipe", id: "fallback", version: "0", title: "环境人像", subtitle: "基础模式",
      nodes: [node], relations: [],
      goals: [
        .init(
          id: "subject_exists", dimension: "std.node.exists",
          binding: .init(scope: "NODE", id: "primary"), target: target, class: "HARD",
          importance: 1, dependencies: [])
      ],
      actions: [],
      authorPolicy: .init(allowGoalSkip: false, allowGoalLock: true, allowVariantSwitch: false),
      perception: .init(
        subjectStrategy: .saliency, semanticHint: nil, faceAssist: false, poseAssist: false,
        anchorStrategy: RecipeAnchorStrategy.none, allowsManualSubjectSelection: true),
      presentation: .init(domain: .general, icon: "viewfinder", tags: []),
      critic: nil
    )
    return CompiledRecipe(
      source: dto, registry: registry, goals: [goal], actions: [action], validationIssues: [])
  }
}
