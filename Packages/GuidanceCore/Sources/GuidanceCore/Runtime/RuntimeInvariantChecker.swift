import Foundation

public enum RuntimeInvariantRule: String, Codable, Sendable {
  case invalidScore
  case invalidConfidence
  case satisfiedWithoutUsableScore
  case activeWithoutScore
  case inactiveDependencyViolation
  case lockStateMismatch
  case infeasibleCurrentAction
  case readyWithUnsatisfiedHardGoal
  case readyWithUnknownHardGoal
  case verificationLifecycleMismatch
  case readyWithPendingAction
  case pausedWithPendingWork
  case userSatisfiedWithPendingAction
  case activePlanTransactionMismatch
  case invalidActivePlanStep
}

public struct RuntimeInvariantIssue: Codable, Equatable, Sendable {
  public let rule: RuntimeInvariantRule
  public let message: String

  public init(rule: RuntimeInvariantRule, message: String) {
    self.rule = rule
    self.message = message
  }
}

/// Debug/telemetry invariant checker. It never mutates controller state and is
/// safe to run after any session transition. These checks catch integration
/// regressions that unit tests may miss once camera, Vision and remote semantic
/// evaluators run asynchronously on a real device.
public struct RuntimeInvariantChecker: Sendable {
  public init() {}

  public func check(
    engine: GoalEngine,
    planner: ActionPlanner,
    currentAction: ActionInstance? = nil,
    activePlan: ActionPlanRuntime? = nil,
    verificationRequestedAfterFrame: Int? = nil,
    userSatisfied: Bool = false,
    runtimePauseReason: RuntimePauseReason? = nil,
    captureState: CaptureState? = nil
  ) -> [RuntimeInvariantIssue] {
    var issues = [RuntimeInvariantIssue]()

    for (id, state) in engine.states {
      if let score = state.score, !score.isFinite || !(0...1).contains(score) {
        issues.append(.init(rule: .invalidScore, message: "\(id.rawValue):\(score)"))
      }
      if let confidence = state.confidence,
        !confidence.isFinite || !(0...1).contains(confidence)
      {
        issues.append(.init(rule: .invalidConfidence, message: "\(id.rawValue):\(confidence)"))
      }

      if state.policy != .skipped {
        if state.state == .satisfied {
          guard let definition = engine.definitions[id], let score = state.score,
            score >= definition.stability.exitThreshold
          else {
            issues.append(
              .init(
                rule: .satisfiedWithoutUsableScore,
                message: id.rawValue
              ))
            continue
          }
        }
        if (state.state == .active || state.state == .drifted) && state.score == nil {
          issues.append(.init(rule: .activeWithoutScore, message: id.rawValue))
        }

        if state.state != .inactive,
          let definition = engine.definitions[id],
          !definition.dependencies.isEmpty
        {
          let parentsReady = definition.dependencies.allSatisfy { parent in
            guard let parentState = engine.states[parent] else { return false }
            return parentState.policy == .skipped || parentState.state == .satisfied
          }
          if !parentsReady {
            issues.append(.init(rule: .inactiveDependencyViolation, message: id.rawValue))
          }
        }
      }

      let plannerLocked = planner.lockedGoals.contains(id)
      if (state.policy == .locked) != plannerLocked {
        issues.append(.init(rule: .lockStateMismatch, message: id.rawValue))
      }
    }

    if let currentAction,
      currentAction.state == .proposed,
      !planner.feasible(currentAction.definition, engine: engine)
    {
      issues.append(
        .init(
          rule: .infeasibleCurrentAction,
          message: currentAction.definition.id.rawValue
        ))
    }

    if currentAction?.state == .verifyRequested {
      if !planner.needsReobserve || verificationRequestedAfterFrame == nil {
        issues.append(
          .init(
            rule: .verificationLifecycleMismatch,
            message: currentAction?.definition.id.rawValue ?? "unknown"
          ))
      }
    } else if verificationRequestedAfterFrame != nil && !planner.needsReobserve {
      issues.append(
        .init(rule: .verificationLifecycleMismatch, message: "orphaned verification frame"))
    }

    if userSatisfied, let currentAction {
      issues.append(
        .init(
          rule: .userSatisfiedWithPendingAction,
          message: currentAction.definition.id.rawValue
        ))
    }

    if captureState == .ready || captureState == .readyByUser, let currentAction {
      issues.append(
        .init(rule: .readyWithPendingAction, message: currentAction.definition.id.rawValue))
    }

    if runtimePauseReason != nil || captureState == .paused {
      if currentAction != nil || activePlan != nil {
        issues.append(.init(rule: .pausedWithPendingWork, message: "pending action/plan"))
      }
    }

    if let activePlan {
      if activePlan.currentStep == nil {
        issues.append(
          .init(
            rule: .invalidActivePlanStep,
            message: "\(activePlan.definition.id.rawValue):\(activePlan.stepIndex)"
          ))
      }
      if let currentAction, activePlan.currentStep?.id != currentAction.definition.id {
        issues.append(
          .init(
            rule: .activePlanTransactionMismatch,
            message:
              "\(activePlan.definition.id.rawValue):\(currentAction.definition.id.rawValue)"
          ))
      }
    }

    if captureState == .ready || captureState == .readyByUser {
      for (id, definition) in engine.definitions where definition.constraint == .hard {
        guard let state = engine.states[id], state.policy != .skipped else { continue }
        if state.state == .unknown || state.state == .unresolved || state.state == .inactive {
          issues.append(.init(rule: .readyWithUnknownHardGoal, message: id.rawValue))
        } else if state.state != .satisfied {
          issues.append(.init(rule: .readyWithUnsatisfiedHardGoal, message: id.rawValue))
        }
      }
    }

    return issues
  }
}
