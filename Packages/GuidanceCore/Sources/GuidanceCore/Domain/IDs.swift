import Foundation

public protocol GuidanceID: Codable, Hashable, Sendable {
    var rawValue: String { get }
    init(_ rawValue: String)
}

public struct NodeID: GuidanceID {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct DimensionID: GuidanceID {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct GoalID: GuidanceID {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct ActionID: GuidanceID {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct EvaluatorID: GuidanceID {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}
