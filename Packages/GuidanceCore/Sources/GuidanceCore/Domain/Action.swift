import Foundation

public enum ActionActor: String, Codable, Sendable {
  case photographer
  case subject
  case camera
  case sceneObject
  case light
  case system
}

public enum ActionOperation: String, Codable, Sendable {
  case move
  case rotate
  case zoom
  case reframe
  case hold
  case wait
  case capture
  case selectAnchor
}

public enum ActionDirection: String, Codable, Sendable {
  case left
  case right
  case up
  case down
  case forward
  case backward
  case towardCamera
  case awayFromCamera
  case none
}

public enum ActionMagnitude: String, Codable, Sendable {
  case tiny
  case small
  case medium
  case large
}

public enum CoordinateFrame: String, Codable, Sendable {
  case imageSpace
  case photographerSpace
  case subjectSpace
  case deviceSpace
  case worldSpace
}

public enum ActionSafetyClass: String, Codable, Sendable {
  case safe
  case contextDependent
  case restricted
}

public enum ActionCondition: Codable, Equatable, Sendable {
  case always
  case goalUnsatisfied(GoalID)
  case continuousBelow(GoalID, Double)
  case continuousAbove(GoalID, Double)
  case ordinalBelow(GoalID, Int)
  case ordinalAbove(GoalID, Int)
  case booleanEquals(GoalID, Bool)
}

public struct ActionEffect: Codable, Equatable, Sendable {
  public let goal: GoalID
  public let expectedImprovement: Double
  public let possibleDamage: Double

  public init(goal: GoalID, expectedImprovement: Double, possibleDamage: Double = 0) {
    self.goal = goal
    self.expectedImprovement = Self.normalized(expectedImprovement, fallback: 0)
    self.possibleDamage = Self.normalized(possibleDamage, fallback: 1)
  }

  private static func normalized(_ value: Double, fallback: Double) -> Double {
    guard value.isFinite else { return fallback }
    return min(max(value, 0), 1)
  }
}

public struct InformationEffect: Codable, Equatable, Sendable {
  public let goal: GoalID
  /// Expected confidence increase (0...1) when the information action succeeds.
  public let confidenceGain: Double
  /// Probability that an UNKNOWN / unresolved goal becomes observable after the action.
  public let resolutionProbability: Double

  public init(
    goal: GoalID,
    confidenceGain: Double,
    resolutionProbability: Double = 1
  ) {
    self.goal = goal
    self.confidenceGain = Self.normalized(confidenceGain)
    self.resolutionProbability = Self.normalized(resolutionProbability)
  }

  private static func normalized(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
  }
}

public struct ActionDefinition: Codable, Equatable, Sendable {
  public let id: ActionID
  public let actor: ActionActor
  public let operation: ActionOperation
  public let direction: ActionDirection
  public let magnitude: ActionMagnitude
  public let coordinateFrame: CoordinateFrame
  public let condition: ActionCondition
  public let effects: [ActionEffect]
  public let informationEffects: [InformationEffect]
  public let burden: Double
  public let risk: Double
  public let uncertainty: Double
  public let family: String
  public let requiredCapability: String?
  public let safety: ActionSafetyClass
  public let presentationKey: String

  public init(
    id: ActionID,
    actor: ActionActor,
    operation: ActionOperation,
    direction: ActionDirection = .none,
    magnitude: ActionMagnitude = .small,
    coordinateFrame: CoordinateFrame = .imageSpace,
    condition: ActionCondition = .always,
    effects: [ActionEffect],
    informationEffects: [InformationEffect] = [],
    burden: Double = 0,
    risk: Double = 0,
    uncertainty: Double = 0,
    family: String = "default",
    requiredCapability: String? = nil,
    safety: ActionSafetyClass = .safe,
    presentationKey: String
  ) {
    self.id = id
    self.actor = actor
    self.operation = operation
    self.direction = direction
    self.magnitude = magnitude
    self.coordinateFrame = coordinateFrame
    self.condition = condition
    self.effects = effects
    self.informationEffects = informationEffects
    self.burden = Self.normalizedCost(burden)
    self.risk = Self.normalizedCost(risk)
    self.uncertainty = Self.normalizedCost(uncertainty)
    self.family = family
    self.requiredCapability = requiredCapability
    self.safety = safety
    self.presentationKey = presentationKey
  }

  private static func normalizedCost(_ value: Double) -> Double {
    guard value.isFinite else { return 1 }
    return min(max(value, 0), 1)
  }

  public var improvedGoals: Set<GoalID> {
    Set(effects.filter { $0.expectedImprovement > 0 }.map(\.goal))
  }
  public var touchedGoals: Set<GoalID> { Set(effects.map(\.goal)) }
  public var informationGoals: Set<GoalID> { Set(informationEffects.map(\.goal)) }
  public var isInformationSeeking: Bool { !informationEffects.isEmpty }
}

public enum ActionState: String, Codable, Sendable {
  case proposed
  case accepted
  case executing
  case partial
  case verifyRequested
  case completed
  case declined
  case cancelled
  case failed
  case blocked
  case skipped
}

public enum ActionVerification: String, Codable, Sendable {
  case improved
  case partial
  case noEffect
  case oppositeEffect
  case inconclusive
}

public struct EvidenceStamp: Codable, Equatable, Sendable {
  public let frameID: Int
  public let bindingVersion: Int
  public let sceneRevision: Int

  public init(frameID: Int, bindingVersion: Int, sceneRevision: Int) {
    self.frameID = frameID
    self.bindingVersion = bindingVersion
    self.sceneRevision = sceneRevision
  }
}

public struct ActionInstance: Codable, Equatable, Sendable {
  public let definition: ActionDefinition
  public var state: ActionState
  public let baselineScores: [GoalID: Double]
  public let baselineEvidence: [GoalID: EvidenceStamp]
  public let baselineConfidence: [GoalID: Double]
  public let verificationGoals: Set<GoalID>
  public var verification: ActionVerification?

  public init(
    _ definition: ActionDefinition,
    baselineScores: [GoalID: Double] = [:],
    baselineEvidence: [GoalID: EvidenceStamp] = [:],
    baselineConfidence: [GoalID: Double] = [:],
    verificationGoals: Set<GoalID>? = nil
  ) {
    self.definition = definition
    self.state = .proposed
    self.baselineScores = baselineScores
    self.baselineEvidence = baselineEvidence
    self.baselineConfidence = baselineConfidence
    self.verificationGoals =
      verificationGoals ?? definition.touchedGoals.union(definition.informationGoals)
  }
}

public struct SessionConstraint: Codable, Hashable, Sendable {
  public let family: String
  public init(family: String) { self.family = family }
}
