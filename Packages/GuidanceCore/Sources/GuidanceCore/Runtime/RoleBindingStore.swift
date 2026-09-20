import Foundation

public enum RoleBindingPolicy: String, Codable, Sendable {
  case sticky
  case autoSubstitutable
  case requireConfirmation
}

public enum RuntimeBindingStatus: String, Codable, Sendable {
  case bound
  case lost
  case pendingConfirmation
}

public struct RuntimeNodeBinding: Codable, Equatable, Sendable {
  public let node: NodeID
  public var track: TrackID?
  public var confidence: Double
  public var status: RuntimeBindingStatus

  public init(
    node: NodeID,
    track: TrackID?,
    confidence: Double,
    status: RuntimeBindingStatus
  ) {
    self.node = node
    self.track = track
    self.confidence = min(max(confidence, 0), 1)
    self.status = status
  }
}

/// Binds semantic recipe nodes to runtime tracks. Version increments whenever
/// identity meaningfully changes so delayed model results can be rejected.
public struct RoleBindingStore: Sendable {
  public private(set) var bindings: [NodeID: RuntimeNodeBinding] = [:]
  public private(set) var version = 0
  public var defaultPolicy: RoleBindingPolicy
  public var policies: [NodeID: RoleBindingPolicy] = [:]

  public init(defaultPolicy: RoleBindingPolicy = .sticky) {
    self.defaultPolicy = defaultPolicy
  }

  public func binding(for node: NodeID) -> RuntimeNodeBinding? { bindings[node] }

  @discardableResult
  public mutating func bind(
    node: NodeID,
    to track: TrackID,
    confidence: Double,
    confirmed: Bool = false
  ) -> Bool {
    let policy = policies[node] ?? defaultPolicy
    if let current = bindings[node], let oldTrack = current.track, oldTrack != track {
      switch policy {
      case .sticky:
        guard confirmed else { return false }
      case .requireConfirmation:
        guard confirmed else {
          bindings[node] = RuntimeNodeBinding(
            node: node, track: oldTrack, confidence: current.confidence,
            status: .pendingConfirmation)
          return false
        }
      case .autoSubstitutable:
        break
      }
    }

    let identityChanged = bindings[node]?.track != track
    bindings[node] = RuntimeNodeBinding(
      node: node, track: track, confidence: confidence, status: .bound)
    if identityChanged { version += 1 }
    return true
  }

  public mutating func markLost(node: NodeID) {
    guard var current = bindings[node] else { return }
    if current.status != .lost {
      current.status = .lost
      current.confidence = 0
      bindings[node] = current
      version += 1
    }
  }

  public mutating func clear(node: NodeID) {
    if bindings.removeValue(forKey: node) != nil { version += 1 }
  }

  public mutating func clearAll() {
    guard !bindings.isEmpty else { return }
    bindings.removeAll()
    version += 1
  }
}
