import Foundation

public enum BindingPolicy: Sendable { case sticky, autoSubstitutable, requireConfirmation }
public struct BindingStore: Sendable { public private(set) var bindings:[String:NodeID]=[:]; public private(set) var version=0; public let policy:BindingPolicy; public init(policy:BindingPolicy = .sticky) { self.policy=policy }; public mutating func bind(role:String,node:NodeID,confirmed:Bool=false)->Bool { if let old=bindings[role], old != node && policy == .sticky && !confirmed { return false }; bindings[role]=node; version += 1; return true } }
