import Foundation

/// The tiny stateful product kernel for multimodal photographic judgment.
///
/// It owns no subject detector, no camera policy and no Recipe-specific branch.
/// Give it a CriticProfile and successive model critiques; it produces one stable
/// decision for the product surface. Local Vision may run beside it, but is not
/// part of this decision kernel.
public struct SemanticCriticSession: Sendable {
  public enum Decision: Equatable, Sendable {
    case evaluating
    case rejected([SemanticCritiqueIssue])
    case ready(score: Double?)
    case advise(CriticAdvice, score: Double?)
    case observe(score: Double?)
  }

  public let profile: CriticProfile
  public var validator: SemanticCritiqueValidator
  public var reducer: SemanticCritiqueReducer
  public var freshnessWindow: TimeInterval
  public var adviceHoldDuration: TimeInterval

  public private(set) var latestCritique: SemanticCritique?
  public private(set) var lastAcceptedAt: Date?
  public private(set) var activeAdvice: CriticAdvice?
  public private(set) var lastIssues: [SemanticCritiqueIssue] = []

  private var adviceHoldUntil = Date.distantPast

  public init(
    profile: CriticProfile,
    validator: SemanticCritiqueValidator = .init(),
    reducer: SemanticCritiqueReducer = .init(),
    freshnessWindow: TimeInterval = 3.2,
    adviceHoldDuration: TimeInterval = 1.25
  ) {
    self.profile = profile
    self.validator = validator
    self.reducer = reducer
    self.freshnessWindow = max(0.2, freshnessWindow)
    self.adviceHoldDuration = max(0, adviceHoldDuration)
  }

  @discardableResult
  public mutating func ingest(_ critique: SemanticCritique, at date: Date = .now) -> Decision {
    let validation = validator.validate(critique, against: profile)
    lastIssues = validation.issues
    guard validation.isUsable else { return .rejected(validation.issues) }

    let accepted = validation.critique
    latestCritique = accepted
    lastAcceptedAt = date

    if reducer.isCaptureReady(accepted, profile: profile) {
      activeAdvice = nil
      adviceHoldUntil = date
      return .ready(score: reducer.overallScore(accepted, profile: profile))
    }

    let candidate = reducer.primaryAdvice(for: accepted, profile: profile)
    if let candidate {
      let sameDimension = candidate.dimensionID == activeAdvice?.dimensionID
      if activeAdvice == nil || sameDimension || date >= adviceHoldUntil {
        activeAdvice = candidate
        adviceHoldUntil = date.addingTimeInterval(adviceHoldDuration)
      }
    }

    return decision(at: date)
  }

  public func decision(at date: Date = .now) -> Decision {
    guard let critique = latestCritique, let acceptedAt = lastAcceptedAt,
      date.timeIntervalSince(acceptedAt) <= freshnessWindow
    else { return .evaluating }

    let score = reducer.overallScore(critique, profile: profile)
    if reducer.isCaptureReady(critique, profile: profile) { return .ready(score: score) }
    if let activeAdvice { return .advise(activeAdvice, score: score) }
    if let fallback = reducer.primaryAdvice(for: critique, profile: profile) {
      return .advise(fallback, score: score)
    }
    return .observe(score: score)
  }

  public mutating func reset() {
    latestCritique = nil
    lastAcceptedAt = nil
    activeAdvice = nil
    lastIssues = []
    adviceHoldUntil = .distantPast
  }
}
