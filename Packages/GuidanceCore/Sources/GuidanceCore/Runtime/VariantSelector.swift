import Foundation

public struct VariantScore: Equatable, Sendable {
    public let id: String
    public let score: Double

    public init(id: String, score: Double) {
        self.id = id
        self.score = score
    }
}

public struct VariantSelector: Sendable {
    public private(set) var currentID: String?
    public var switchMargin: Double
    public var requiredConfirmations: Int

    private var pendingID: String?
    private var pendingCount = 0

    public init(
        currentID: String? = nil,
        switchMargin: Double = 0.05,
        requiredConfirmations: Int = 2
    ) {
        self.currentID = currentID
        self.switchMargin = switchMargin
        self.requiredConfirmations = max(1, requiredConfirmations)
    }

    @discardableResult
    public mutating func select(from variants: [VariantScore]) -> String? {
        guard let best = variants.max(by: { $0.score < $1.score }) else { return currentID }
        guard let currentID else {
            self.currentID = best.id
            return best.id
        }
        guard best.id != currentID else {
            pendingID = nil
            pendingCount = 0
            return currentID
        }

        let currentScore = variants.first(where: { $0.id == currentID })?.score ?? -.infinity
        guard best.score >= currentScore + switchMargin else {
            pendingID = nil
            pendingCount = 0
            return currentID
        }

        if pendingID == best.id {
            pendingCount += 1
        } else {
            pendingID = best.id
            pendingCount = 1
        }

        if pendingCount >= requiredConfirmations {
            self.currentID = best.id
            pendingID = nil
            pendingCount = 0
        }

        return self.currentID
    }
}
