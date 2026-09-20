import Foundation

public enum ScoreState: Equatable, Sendable {
    case satisfied
    case unsatisfied
    case unknown
}

public enum Scoring {
    public static func band(_ value: Double, _ target: TargetBand) -> Double {
        guard target.acceptable.contains(value) else { return 0 }
        if target.ideal.contains(value) { return 1 }

        if value < target.ideal.lowerBound {
            let width = target.ideal.lowerBound - target.acceptable.lowerBound
            return max(0, 1 - (target.ideal.lowerBound - value) / max(width, 0.000_001))
        }

        let width = target.acceptable.upperBound - target.ideal.upperBound
        return max(0, 1 - (value - target.ideal.upperBound) / max(width, 0.000_001))
    }

    public static func ordinal(_ value: Int, target: Int) -> Double {
        max(0, 1 - Double(abs(value - target)) / 3)
    }

    public static func evaluate(
        _ observation: Observation,
        target: GoalTarget
    ) -> (score: Double, state: ScoreState) {
        let score: Double

        switch (observation.value, target) {
        case let (.continuous(value), .band(band)):
            score = self.band(value, band)

        case let (.ordinal(value), .ordinal(targetValue)):
            if let distribution = observation.distribution, !distribution.isEmpty {
                score = distribution.reduce(into: 0) { total, item in
                    guard let candidate = Int(item.key) else { return }
                    total += ordinal(candidate, target: targetValue) * item.value
                }
            } else {
                score = ordinal(value, target: targetValue)
            }

        case let (.boolean(value), .boolean(targetValue)):
            score = value == targetValue ? 1 : 0

        case let (.categorical(value), .categorical(targetValue)):
            score = value == targetValue ? 1 : 0

        default:
            return (0, .unknown)
        }

        return (score, score >= 0.999 ? .satisfied : .unsatisfied)
    }
}
