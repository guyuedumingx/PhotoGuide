# PhotoGuide v0.3.9

## Theme: Core API freeze and failure-path audit

v0.3.9 deliberately adds almost no new photography concepts. It closes state-lifecycle and replay gaps before the project moves back to iPhone integration and visual polish.

### Runtime input boundary

- Added explicit replay/runtime inputs for processed empty frames, device capabilities, safety clearance, user override reset and checkpoint restore.
- Added `GuidanceRuntimeActor.advanceFrame` and `updateCapabilities` parity with `GuidanceSession`.
- `lastObservedFrame` now acts as the monotonic **processed-frame controller clock** for timeout semantics, including valid observations that do not map to a Goal.
- `advanceFrame` is restricted by contract to processed frames that produced no usable observations.
- Local iOS perception now sends all dimensions from one frame through one `ingestBatch`, so verification cannot time out halfway through the same physical frame.

### Transaction lifecycle audit

Fixed stale verification/re-observation latches after user intent changes:

- `anotherWay` clears pending verification;
- `impossible` clears pending verification;
- `satisfied` cancels pending Action/Plan and clears verification immediately;
- skipping the Goal affected by the current transaction cancels that transaction;
- locking a Goal cancels a transaction that could damage it.

Snapshot telemetry now includes Action/Plan states, plan step, verification pending, user-satisfied state, capabilities, constraints, safety clearances and tick sequence.

Runtime invariants now detect verification lifecycle mismatches, READY/user-satisfied with pending work, paused runtime with pending work, plan/transaction mismatch and invalid active plan steps.

### Deterministic replay completeness

- A successful checkpoint restore is a replay event, making the post-restore log self-contained.
- Capability and safety state changes are replayed instead of being hidden mutations.
- Scene-condition reset to `nil` is now explicitly replayed; previously a replay could incorrectly retain the prior low-light/motion profile after the live session had cleared it.
- Extended replay events round-trip through Codable.

### Checkpoint schema v2

- Definition signatures now include the Registry contract: Nodes, Relations, Dimensions and Evaluators, not only Goals/Actions/Goal Groups.
- A Recipe that reuses IDs but changes its evaluator/dimension contract no longer accepts stale calibration.
- Schema-v1 migration remains supported with structural checks and reliability sanitization against the current Registry.
- Restored evaluator priors are refreshed from the current Registry and removed when the evaluator/dimension no longer exists.

### Defensive cleanup

- Removed avoidable force unwraps in action planning/stabilization paths.
- Removed `try!` JSON construction from RecipeKit's emergency Recipe; the fallback target is now constructed directly.
- The only remaining `fatalError()` is the `@available(*, unavailable)` UIKit coder initializer for the programmatic camera preview view.

## Validation

- GuidanceCore: 128 tests, 0 failures.
- RecipeKit: 6 tests, 0 failures.
- All Swift sources: `swiftc -parse` pass on Linux.
- AVFoundation / Vision / SwiftUI linking still requires macOS + Xcode; this release does not claim device validation.
