import Foundation

/// Session-local empirical calibration for an action. It never changes the
/// published Recipe/Registry; it only adapts planning to the current scene and
/// the current user's execution during one capture session.
public struct ActionEffectStats: Codable, Equatable, Sendable {
  public private(set) var attempts: Int = 0
  public private(set) var improved: Int = 0
  public private(set) var partial: Int = 0
  public private(set) var noEffect: Int = 0
  public private(set) var opposite: Int = 0
  public private(set) var inconclusive: Int = 0

  /// EWMA of observed action quality in [0, 1]. New actions start neutral.
  public private(set) var effectiveness: Double = 0.70
  /// EWMA absolute prediction error. Higher values reduce planner confidence.
  public private(set) var calibrationError: Double = 0.30

  public init() {}

  public mutating func record(_ result: ActionVerification, alpha: Double = 0.35) {
    let a = min(max(alpha, 0.05), 1)
    attempts += 1

    let observedQuality: Double
    switch result {
    case .improved:
      improved += 1
      observedQuality = 1.0
    case .partial:
      partial += 1
      observedQuality = 0.58
    case .noEffect:
      noEffect += 1
      observedQuality = 0.12
    case .oppositeEffect:
      opposite += 1
      observedQuality = 0.0
    case .inconclusive:
      inconclusive += 1
      // Inconclusive evidence should not aggressively punish an action.
      observedQuality = effectiveness
    }

    let predictionError = abs(observedQuality - effectiveness)
    effectiveness = Self.clamp((1 - a) * effectiveness + a * observedQuality)
    calibrationError = Self.clamp((1 - a) * calibrationError + a * predictionError)
  }

  /// Prior-preserving multiplier. One bad attempt cannot erase a useful action,
  /// while repeated failures/opposite effects make alternatives preferable.
  public var gainMultiplier: Double {
    guard attempts >= 2 else { return 1.0 }
    return min(max(0.25 + effectiveness, 0.25), 1.25)
  }

  public var uncertaintyPenalty: Double {
    guard attempts >= 2 else { return 0 }
    return min(0.35, calibrationError * 0.45)
  }

  private static func clamp(_ value: Double) -> Double {
    guard value.isFinite else { return 0.5 }
    return min(max(value, 0), 1)
  }
}

public struct SessionEffectModel: Codable, Equatable, Sendable {
  public private(set) var byAction: [ActionID: ActionEffectStats] = [:]
  public private(set) var byFamily: [String: ActionEffectStats] = [:]

  public init() {}

  public mutating func record(_ result: ActionVerification, for action: ActionDefinition) {
    var actionStats = byAction[action.id] ?? ActionEffectStats()
    actionStats.record(result)
    byAction[action.id] = actionStats

    var familyStats = byFamily[action.family] ?? ActionEffectStats()
    familyStats.record(result, alpha: 0.22)
    byFamily[action.family] = familyStats
  }

  public func gainMultiplier(for action: ActionDefinition) -> Double {
    let direct = byAction[action.id]
    let family = byFamily[action.family]
    switch (direct, family) {
    case (.some(let d), .some(let f)):
      // Direct evidence is more specific; family evidence helps before enough
      // attempts have accumulated for an individual action.
      let directWeight = min(0.8, Double(d.attempts) / 4.0)
      return directWeight * d.gainMultiplier + (1 - directWeight) * f.gainMultiplier
    case (.some(let d), .none): return d.gainMultiplier
    case (.none, .some(let f)): return f.gainMultiplier
    case (.none, .none): return 1.0
    }
  }

  public func uncertaintyPenalty(for action: ActionDefinition) -> Double {
    let direct = byAction[action.id]?.uncertaintyPenalty ?? 0
    let family = byFamily[action.family]?.uncertaintyPenalty ?? 0
    return min(0.4, direct * 0.75 + family * 0.25)
  }
}
