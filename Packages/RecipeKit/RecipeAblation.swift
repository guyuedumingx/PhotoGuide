import Foundation
import GuidanceCore

public struct RecipeAblationProfile: Equatable, Sendable {
  public let id: String
  public let enabledEvaluators: Set<EvaluatorID>

  public init(id: String, enabledEvaluators: Set<EvaluatorID>) {
    self.id = id
    self.enabledEvaluators = enabledEvaluators
  }

  /// Normal shipping fallback when remote semantic inference is unavailable.
  public static let localOnly = RecipeAblationProfile(
    id: "local-only",
    enabledEvaluators: [
      EvaluatorID("vision.local"),
      EvaluatorID("vision.saliency_subject"),
      EvaluatorID("vision.saliency_relation"),
      EvaluatorID("vision.frame"),
      EvaluatorID("core.fusion"),
    ])

  /// Removes both frame-level measurement and remote semantics. This profile is
  /// intentionally harsh and is used to expose Recipes that secretly assume a
  /// portrait geometry detector is the entire product.
  public static let subjectGeometryOnly = RecipeAblationProfile(
    id: "subject-geometry-only",
    enabledEvaluators: [
      EvaluatorID("vision.local"),
      EvaluatorID("vision.saliency_subject"),
      EvaluatorID("vision.saliency_relation"),
      EvaluatorID("core.fusion"),
    ])

  /// Frame-only mode models landscape/architecture operation even when no
  /// reliable discrete primary subject can be acquired.
  public static let frameOnly = RecipeAblationProfile(
    id: "frame-only",
    enabledEvaluators: [EvaluatorID("vision.frame"), EvaluatorID("core.fusion")])

  public static let full = RecipeAblationProfile(
    id: "full",
    enabledEvaluators: [
      EvaluatorID("vision.local"),
      EvaluatorID("vision.saliency_subject"),
      EvaluatorID("vision.saliency_relation"),
      EvaluatorID("vision.frame"),
      EvaluatorID("djev.semantic"),
      EvaluatorID("core.fusion"),
    ])
}

public struct RecipeAblationResult: Equatable, Sendable {
  public let profileID: String
  public let criticalGoalCount: Int
  public let observableCriticalGoals: Set<GoalID>
  public let blockedCriticalGoals: Set<GoalID>
  public let observableSoftGoals: Set<GoalID>

  public var criticalCoverage: Double {
    guard criticalGoalCount > 0 else { return 1 }
    return Double(observableCriticalGoals.count) / Double(criticalGoalCount)
  }

  public var readinessCanBeEvaluated: Bool { blockedCriticalGoals.isEmpty }
}

/// Static evaluator-removal experiment used in CI and release audit.
///
/// It does not claim to measure photographic quality. It answers the narrower
/// production question: if an evaluator family disappears, can every HARD/CORE
/// goal in a Recipe still be observed, or does the control loop become
/// structurally impossible before the user even takes a photo?
public struct RecipeAblationAnalyzer: Sendable {
  public init() {}

  public func analyze(
    _ recipe: CompiledRecipe,
    profile: RecipeAblationProfile
  ) -> RecipeAblationResult {
    var observableCritical = Set<GoalID>()
    var blockedCritical = Set<GoalID>()
    var observableSoft = Set<GoalID>()

    for goal in recipe.goals {
      let evaluators = recipe.registry.dimensions[goal.dimension]?.evaluatorIDs ?? []
      let observable = !evaluators.intersection(profile.enabledEvaluators).isEmpty
      if goal.constraint == .soft {
        if observable { observableSoft.insert(goal.id) }
      } else if observable {
        observableCritical.insert(goal.id)
      } else {
        blockedCritical.insert(goal.id)
      }
    }

    return RecipeAblationResult(
      profileID: profile.id,
      criticalGoalCount: recipe.goals.filter { $0.constraint != .soft }.count,
      observableCriticalGoals: observableCritical,
      blockedCriticalGoals: blockedCritical,
      observableSoftGoals: observableSoft)
  }

  public func analyzeCatalog(
    _ recipes: [CompiledRecipe],
    profiles: [RecipeAblationProfile] = [.localOnly, .subjectGeometryOnly, .frameOnly, .full]
  ) -> [String: [RecipeAblationResult]] {
    Dictionary(uniqueKeysWithValues: recipes.map { recipe in
      (recipe.source.id, profiles.map { analyze(recipe, profile: $0) })
    })
  }
}

// MARK: - Semantic-first product ablation

public struct CriticAblationProfile: Equatable, Sendable {
  public let id: String
  public let criticEnabled: Bool
  public let localAssistEnabled: Bool
  public let sampleCount: Int
  public let domainRubricEnabled: Bool

  public init(
    id: String,
    criticEnabled: Bool,
    localAssistEnabled: Bool,
    sampleCount: Int,
    domainRubricEnabled: Bool
  ) {
    self.id = id
    self.criticEnabled = criticEnabled
    self.localAssistEnabled = localAssistEnabled
    self.sampleCount = max(0, sampleCount)
    self.domainRubricEnabled = domainRubricEnabled
  }

  public static let full = CriticAblationProfile(
    id: "full", criticEnabled: true, localAssistEnabled: true, sampleCount: 3,
    domainRubricEnabled: true)

  /// Product-critical experiment: removing every local Vision assist must not
  /// remove any model-scored photographic quality dimension.
  public static let criticOnly = CriticAblationProfile(
    id: "critic-only", criticEnabled: true, localAssistEnabled: false, sampleCount: 3,
    domainRubricEnabled: true)

  /// Measures the structural loss of temporal context while preserving the same
  /// multimodal critic and domain rubric.
  public static let singleFrameCritic = CriticAblationProfile(
    id: "single-frame-critic", criticEnabled: true, localAssistEnabled: false, sampleCount: 1,
    domainRubricEnabled: true)

  /// Removes Recipe-specific photographic expertise while keeping a generic critic.
  public static let genericRubric = CriticAblationProfile(
    id: "generic-rubric", criticEnabled: true, localAssistEnabled: false, sampleCount: 3,
    domainRubricEnabled: false)

  /// Diagnostic fallback only. This is intentionally *not* considered the full
  /// PhotoGuide product because it has no professional multimodal image critique.
  public static let localOnly = CriticAblationProfile(
    id: "local-only", criticEnabled: false, localAssistEnabled: true, sampleCount: 0,
    domainRubricEnabled: false)
}

public struct CriticAblationResult: Equatable, Sendable {
  public let profileID: String
  public let totalQualityDimensions: Int
  public let activeQualityDimensions: Int
  public let professionalAdviceAvailable: Bool
  public let temporalContextAvailable: Bool
  public let domainSpecificRubricAvailable: Bool
  public let localAssistAvailable: Bool

  public var qualityDimensionCoverage: Double {
    guard totalQualityDimensions > 0 else { return 1 }
    return Double(activeQualityDimensions) / Double(totalQualityDimensions)
  }

  public var fullProductCapability: Bool {
    professionalAdviceAvailable && qualityDimensionCoverage == 1 && domainSpecificRubricAvailable
  }
}

public struct CriticAblationAnalyzer: Sendable {
  private static let genericDimensionIDs: Set<String> = [
    "composition", "lighting", "light", "color", "overall",
  ]

  public init() {}

  public func analyze(_ recipe: CompiledRecipe, profile: CriticAblationProfile)
    -> CriticAblationResult
  {
    let critic = recipe.source.resolvedCritic
    let total = critic.dimensions.count
    let active: Int
    if !profile.criticEnabled {
      active = 0
    } else if profile.domainRubricEnabled {
      active = total
    } else {
      active = critic.dimensions.filter { Self.genericDimensionIDs.contains($0.id) }.count
    }

    return CriticAblationResult(
      profileID: profile.id,
      totalQualityDimensions: total,
      activeQualityDimensions: active,
      professionalAdviceAvailable: profile.criticEnabled,
      temporalContextAvailable: profile.criticEnabled && profile.sampleCount > 1,
      domainSpecificRubricAvailable: profile.criticEnabled && profile.domainRubricEnabled,
      localAssistAvailable: profile.localAssistEnabled)
  }
}
