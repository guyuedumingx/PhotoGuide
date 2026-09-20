import Foundation

public enum EvaluatorFaultKind: String, Codable, Sendable {
  case timeout
  case transport
  case invalidPayload
  case rejectedOutput
  case unavailable
}

public enum EvaluatorCircuitState: String, Codable, Sendable {
  case closed
  case degraded
  case open
}

public struct EvaluatorHealthPolicy: Codable, Equatable, Sendable {
  public var degradeAfterFailures: Int
  public var openAfterFailures: Int
  public var cooldownFrames: Int

  public init(
    degradeAfterFailures: Int = 2,
    openAfterFailures: Int = 4,
    cooldownFrames: Int = 24
  ) {
    self.degradeAfterFailures = max(1, degradeAfterFailures)
    self.openAfterFailures = max(self.degradeAfterFailures, openAfterFailures)
    self.cooldownFrames = max(1, cooldownFrames)
  }
}

public struct EvaluatorHealthState: Codable, Equatable, Sendable {
  public var circuit: EvaluatorCircuitState = .closed
  public var consecutiveFailures = 0
  public var totalFailures = 0
  public var totalSuccesses = 0
  public var invalidPayloads = 0
  public var lastFailure: EvaluatorFaultKind?
  public var lastFailureFrame: Int?
  public var lastSuccessFrame: Int?
  public var nextProbeFrame: Int?

  public init() {}
}

/// Session-local circuit breaker for evaluator faults. It is deterministic and
/// frame-based so replay/tests do not depend on wall-clock timing.
public struct EvaluatorHealthMonitor: Codable, Equatable, Sendable {
  public var policy: EvaluatorHealthPolicy
  public private(set) var states: [EvaluatorID: EvaluatorHealthState] = [:]

  public init(policy: EvaluatorHealthPolicy = .init()) {
    self.policy = policy
  }

  public func state(for evaluator: EvaluatorID) -> EvaluatorHealthState {
    states[evaluator] ?? EvaluatorHealthState()
  }

  /// Open evaluators are quarantined until the deterministic probe frame.
  public func isSchedulable(_ evaluator: EvaluatorID, frameID: Int) -> Bool {
    let state = state(for: evaluator)
    switch state.circuit {
    case .closed, .degraded:
      return true
    case .open:
      return frameID >= (state.nextProbeFrame ?? Int.max)
    }
  }

  public mutating func recordSuccess(_ evaluator: EvaluatorID, frameID: Int) {
    var state = state(for: evaluator)
    state.totalSuccesses += 1
    state.lastSuccessFrame = frameID
    state.consecutiveFailures = 0
    state.lastFailure = nil
    state.nextProbeFrame = nil
    state.circuit = .closed
    states[evaluator] = state
  }

  public mutating func recordFailure(
    _ evaluator: EvaluatorID,
    kind: EvaluatorFaultKind,
    frameID: Int
  ) {
    var state = state(for: evaluator)
    state.totalFailures += 1
    state.consecutiveFailures += 1
    state.lastFailure = kind
    state.lastFailureFrame = frameID
    if kind == .invalidPayload || kind == .rejectedOutput { state.invalidPayloads += 1 }

    if state.consecutiveFailures >= policy.openAfterFailures || state.circuit == .open {
      state.circuit = .open
      state.nextProbeFrame = frameID + policy.cooldownFrames
    } else if state.consecutiveFailures >= policy.degradeAfterFailures {
      state.circuit = .degraded
    }
    states[evaluator] = state
  }

  public mutating func reset(_ evaluator: EvaluatorID? = nil) {
    if let evaluator {
      states.removeValue(forKey: evaluator)
    } else {
      states.removeAll()
    }
  }
}
