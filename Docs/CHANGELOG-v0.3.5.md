# PhotoGuide v0.3.5

## Core reliability

- Added deterministic `GuidanceReplayEvent` recording and `GuidanceReplayer`.
- Replay log captures raw observations before validation, user events and explicit controller ticks.
- Replay outputs normalized decisions, final snapshot and invariant issues.
- Replay storage is bounded by a configurable capacity.
- `UserEvent` is now Codable/Equatable for durable debug fixtures.

## Evaluation scheduling

- Added stateful `EvaluationCoordinator`.
- Added independent local/semantic cadence budgets for Guard / Focus / Watch goals.
- HARD guards may remain high-frequency while satisfied Watch goals are periodically sampled.
- Action/dependency invalidation bypasses cadence throttling so regressions are re-evaluated immediately.

## Runtime auditability

- Added the explicit 14-phase `RuntimeTickPhase` contract.
- Added `RuntimeTickReport` and `GuidanceSession.tickDetailed()`.
- Detailed ticks expose work sets, normalized decision, readiness and runtime invariant violations.
- `GuidanceRuntimeActor` exposes detailed tick reports and replay events without leaking mutable session state.

## Verification

- GuidanceCore: 87 tests, 0 failures.
- RecipeKit tests re-run from clean build.
- All Swift sources parsed successfully in the Linux validation environment.
