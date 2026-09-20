import Foundation

public struct FreshnessEvaluator: Sendable {
  public var maxFrameDelta = 6
  public var maxSceneDelta = 0
  public var maxAge: TimeInterval = 2.0
  public var futureClockTolerance: TimeInterval = 0.25

  public init() {}

  public func accepts(
    result: Observation,
    currentFrame: Int,
    currentBindingVersion: Int,
    currentSceneRevision: Int,
    now: Date = .now
  ) -> Bool {
    guard result.frameID <= currentFrame,
      currentFrame - result.frameID <= maxFrameDelta,
      result.bindingVersion == currentBindingVersion,
      abs(result.sceneRevision - currentSceneRevision) <= maxSceneDelta
    else { return false }

    let age = now.timeIntervalSince(result.timestamp)
    return age >= -futureClockTolerance && age <= maxAge
  }
}
