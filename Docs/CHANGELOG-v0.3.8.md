# PhotoGuide v0.3.8

## Fault containment + adaptive runtime budget + checkpoint recovery

### Evaluator circuit breaker

- Added `EvaluatorHealthMonitor` with deterministic frame-based `closed / degraded / open` circuit states.
- Consecutive timeout/transport/invalid-output failures quarantine an evaluator instead of letting it repeatedly consume latency and battery.
- Open evaluators are eligible only after a cooldown probe frame; one successful probe closes the circuit.
- `EvaluationPlanner` can filter unavailable evaluators without changing Recipe/Dimension definitions.
- `GuidanceUI` now records DJev success, timeout, transport, decode, and rejected-output outcomes into the coordinator.
- Remote semantic failure remains additive: local Vision guidance stays live.

### Adaptive runtime budget

- Added `RuntimeResourcePressure` and `RuntimeBudgetProfile`.
- Evaluation cadence and slot budgets now adapt to nominal / constrained / critical resource pressure.
- HARD guard slots are never discarded merely to satisfy a budget cap; focus/watch work is shed first.
- Semantic watch work is disabled under constrained/critical pressure and semantic batch size is reduced.
- iOS host maps system thermal state into the core resource-pressure model before semantic scheduling.

### Safe runtime interruption semantics

- Added `pauseRuntime` / `resumeRuntime` to `GuidanceSession` and `GuidanceRuntimeActor`.
- Camera/background interruption cancels transient Action/Plan execution without rollback.
- Resume explicitly discards scene-bound evidence and requires fresh observations before READY can return.
- Runtime pause/resume is represented in deterministic replay and exported through `GuidanceSnapshot`.

### Checkpoint / recovery

- Added versioned `GuidanceSessionCheckpoint` with a full structural recipe signature.
- Restore rejects checkpoints when Goal targets, dependencies, Action effects/safety semantics, or Goal Groups changed even if IDs are unchanged.
- Checkpoint preserves session-local user constraints, locks, controller/effect memory, and evaluator reliability.
- Physical-context state is deliberately not restored: camera capabilities, safety clearances, active Action/Plan, observations, READY state, and user-satisfied override are discarded.
- Added an iOS `SessionCheckpointStore` using atomic Application Support writes with a 30-minute TTL for background/process-death recovery.

## Verification

- GuidanceCore: 114 tests, 0 failures.
- RecipeKit: 6 tests, 0 failures.
- All Swift source files pass syntax parsing in the current environment.
- AVFoundation/Vision/SwiftUI linking and device behavior still require macOS/Xcode and a physical iPhone.
