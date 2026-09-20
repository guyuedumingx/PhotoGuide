import Foundation

public protocol GuidanceID: Codable, Hashable, Sendable, CustomStringConvertible {
  var rawValue: String { get }
  init(_ rawValue: String)
}

extension GuidanceID {
  public var description: String { rawValue }
}

public struct NodeID: GuidanceID {
  public let rawValue: String
  public init(_ rawValue: String) { self.rawValue = rawValue }
}
public struct TrackID: GuidanceID {
  public let rawValue: String
  public init(_ rawValue: String) { self.rawValue = rawValue }
}
public struct RelationID: GuidanceID {
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
public struct GoalGroupID: GuidanceID {
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

public struct ActionPlanID: GuidanceID {
  public let rawValue: String
  public init(_ rawValue: String) { self.rawValue = rawValue }
}
