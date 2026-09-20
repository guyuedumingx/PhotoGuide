import Foundation

public enum ScoreState: Equatable, Sendable { case satisfied, unsatisfied, unknown }

public enum Scoring {
  public static func band(_ value: Double, _ target: TargetBand) -> Double {
    guard value.isFinite, target.isWellFormed else { return 0 }
    guard target.acceptable.contains(value) else { return 0 }
    if target.ideal.contains(value) { return 1 }
    if value < target.ideal.lowerBound {
      let width = target.ideal.lowerBound - target.acceptable.lowerBound
      let t = (value - target.acceptable.lowerBound) / max(width, 0.000_001)
      return 0.55 + 0.45 * min(max(t, 0), 1)
    }
    let width = target.acceptable.upperBound - target.ideal.upperBound
    let t = (target.acceptable.upperBound - value) / max(width, 0.000_001)
    return 0.55 + 0.45 * min(max(t, 0), 1)
  }

  public static func ordinal(_ value: Int, target: Int) -> Double {
    max(0, 1 - Double(abs(value - target)) / 3)
  }

  public static func evaluate(_ observation: Observation, target: GoalTarget) -> (
    score: Double, state: ScoreState
  ) {
    let score: Double
    switch (observation.value, target) {
    case (.continuous(let value), .band(let band)):
      guard value.isFinite, band.isWellFormed else { return (0, .unknown) }
      score = self.band(value, band)

    case (.ordinal(let value), .ordinal(let targetValue)):
      if let distribution = observation.distribution, !distribution.isEmpty {
        let valid = distribution.compactMap { key, probability -> (Int, Double)? in
          guard let candidate = Int(key), probability.isFinite, probability > 0 else { return nil }
          return (candidate, probability)
        }
        let mass = valid.reduce(0.0) { $0 + $1.1 }
        guard mass > 0 else { return (0, .unknown) }
        score = valid.reduce(0.0) { partial, item in
          partial + ordinal(item.0, target: targetValue) * (item.1 / mass)
        }
      } else {
        score = ordinal(value, target: targetValue)
      }

    case (.boolean(let value), .boolean(let targetValue)):
      score = value == targetValue ? 1 : 0

    case (.categorical(let value), .categorical(let targetValue)):
      guard !value.isEmpty, !targetValue.isEmpty else { return (0, .unknown) }
      score = value == targetValue ? 1 : 0

    default:
      return (0, .unknown)
    }

    guard score.isFinite else { return (0, .unknown) }
    let clamped = min(max(score, 0), 1)
    return (clamped, clamped >= 0.999 ? .satisfied : .unsatisfied)
  }
}
