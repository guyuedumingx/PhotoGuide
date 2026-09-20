import Foundation

public struct FreshnessEvaluator: Sendable {
    public var maxFrameDelta = 5
    public var maxSceneDelta = 1
    public init() {}
    public func accepts(result: Observation, currentFrame: Int, currentBindingVersion: Int, currentSceneRevision: Int) -> Bool {
        result.frameID <= currentFrame && currentFrame - result.frameID <= maxFrameDelta && result.bindingVersion == currentBindingVersion && abs(result.sceneRevision - currentSceneRevision) <= maxSceneDelta
    }
}
