import Foundation

public enum RuntimeResourcePressure: String, Codable, Sendable {
  case nominal
  case constrained
  case critical
}

public struct RuntimeBudgetProfile: Codable, Equatable, Sendable {
  public let intervalMultiplier: Int
  public let maxLocalSlotsPerFrame: Int
  public let maxSemanticSlotsPerFrame: Int
  public let allowSemanticWatch: Bool

  public init(
    intervalMultiplier: Int,
    maxLocalSlotsPerFrame: Int,
    maxSemanticSlotsPerFrame: Int,
    allowSemanticWatch: Bool
  ) {
    self.intervalMultiplier = max(1, intervalMultiplier)
    self.maxLocalSlotsPerFrame = max(1, maxLocalSlotsPerFrame)
    self.maxSemanticSlotsPerFrame = max(0, maxSemanticSlotsPerFrame)
    self.allowSemanticWatch = allowSemanticWatch
  }

  public static func profile(for pressure: RuntimeResourcePressure) -> Self {
    switch pressure {
    case .nominal:
      .init(
        intervalMultiplier: 1,
        maxLocalSlotsPerFrame: 16,
        maxSemanticSlotsPerFrame: 8,
        allowSemanticWatch: true
      )
    case .constrained:
      .init(
        intervalMultiplier: 2,
        maxLocalSlotsPerFrame: 10,
        maxSemanticSlotsPerFrame: 4,
        allowSemanticWatch: false
      )
    case .critical:
      .init(
        intervalMultiplier: 3,
        maxLocalSlotsPerFrame: 6,
        maxSemanticSlotsPerFrame: 1,
        allowSemanticWatch: false
      )
    }
  }
}
