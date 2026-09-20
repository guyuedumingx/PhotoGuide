# GuidanceCore host API freeze — v0.3.9

v0.3.9 freezes the host-facing runtime contract before the first serious iPhone integration pass. The goal is not binary/API compatibility forever; it is to stop bypassing the session boundary while device work begins.

## Production entry point

`GuidanceSession` owns controller state. If callers can arrive from multiple executors, use `GuidanceRuntimeActor` rather than sharing a session directly. `GuidanceUI` is `@MainActor` and may use one session on the main actor.

Production host code should change runtime state through the methods below rather than mutating `GoalEngine` or `ActionPlanner` internals. Direct engine/planner mutation remains available for tests and diagnostics in v0.3.9 so the source tree is not broken immediately before Xcode validation.

| Input / operation | API | Contract |
| --- | --- | --- |
| One asynchronous evaluator result | `ingest(_:)` | Use for a genuinely independent result such as delayed semantic output. |
| All observations produced by one processed local frame | `ingestBatch(_:)` | Atomic frame boundary. Do not split dimensions from the same local frame into separate calls. |
| Processed frame with no usable observation | `advanceFrame(_:)` | Advances verification timeout. Do **not** call before/after `ingestBatch` for the same frame. |
| Sensing quality | `updateSceneConditions(_:)` | Pass `nil` when the condition profile clears; both set and reset are replayed. |
| Device capabilities | `updateCapabilities(_:)` | Replace the complete current capability set; do not mutate planner capabilities directly. |
| User intent | `handle(_:)` | `done`, alternative, impossible, cancel, lock, skip, satisfied, resume guidance. |
| Physical safety permission | `grantSafetyClearance` / `revokeSafetyClearance` | Session-local only. Never persisted through checkpoint restore. |
| Runtime interruption | `pauseRuntime` / `resumeRuntime` | Resume invalidates stale scene evidence and requires re-observation. |
| Persistence | `checkpoint()` / `restore(from:)` | Restores preferences/calibration, not physical scene state. |
| Controller decision | `tick()` | Mutating decision tick. |
| Auditable decision | `tickDetailed()` | Runs one normal tick, then reports declared phase order, work sets, readiness and invariants. |
| Debug state | `snapshot()` / `invariantIssues()` / `replayEvents` | Non-authoritative telemetry and reproducibility surfaces. |

## Atomic frame rule

A local perception pass is one transaction from the controller's point of view:

```text
Camera frame N
  -> local evaluators
  -> [Observation A, B, C, ...]
  -> session.ingestBatch(...)
  -> verification / state transition
```

Calling `ingest` once per local dimension can create an ordering race at a verification-timeout boundary: an early dimension could time out the transaction before a later dimension from the same physical frame supplies the evidence needed to verify it. v0.3.9's iOS host uses `ingestBatch` for this reason.

`advanceFrame` has a deliberately narrow meaning: a frame reached the controller's perception boundary but yielded no usable observations. Raw preview frames that perception never processed must not advance this clock.

## User-intent lifecycle rules

User intent is authoritative without falsifying Recipe conformance:

- `done` starts verification and waits for post-action evidence.
- `anotherWay` declines the current action instance and clears pending verification.
- `impossible` blocks that action family for the session and clears pending verification.
- `cancel` cancels the transaction/plan and intentionally requests re-observation from the current physical state; no rollback is invented.
- `lock(goal)` may invalidate work that could damage the locked goal.
- `skip(goal)` is allowed only when the Goal definition is skippable and aborts work tied to that goal.
- `satisfied` cancels pending work immediately and may produce `READY_BY_USER`, but cannot override a failing HARD guard.

The runtime invariant checker audits orphaned verification state, READY with pending work, paused state with pending work, active-plan/transaction mismatches and invalid plan-step indices.

## Replay contract

Replay is an external-input log, not a serialized dump of derived controller state. v0.3.9 records:

- individual observations and atomic observation batches;
- processed empty frames;
- scene-condition set **and reset**;
- device capability changes;
- safety-clearance grant/revoke;
- user-override reset;
- checkpoint restore;
- runtime pause/resume;
- user events;
- explicit decision ticks.

This makes a post-restore session reproducible without relying on hidden pre-restore state.

## Checkpoint schema v2

Schema v2 fingerprints not only goals/actions/groups but the runtime Registry contract: Nodes, Relations, Dimensions and Evaluators. This prevents learned evaluator reliability from being restored against a changed measurement/evaluator schema that happens to reuse the same Recipe IDs.

Schema v1 checkpoints remain readable as a migration path. Their structural Recipe signature is checked and evaluator reliability is sanitized against the current Registry before use. Unknown evaluators/dimensions and stale priors are discarded or refreshed from current Registry defaults.

Checkpoint restore intentionally does **not** restore:

- old observations or READY state;
- active Action/Plan/verification transaction;
- safety clearances;
- current hardware capabilities;
- physical camera/scene state.

## Freeze boundary

Until the first macOS/Xcode and device pass is complete, avoid introducing new core primitives or bypass APIs. Changes should preferably fall into one of four categories:

1. bug/failure-path fixes;
2. instrumentation needed to reproduce device behavior;
3. adapter work required by AVFoundation/Vision/DJev integration;
4. source-compatible cleanup proven by the package tests.

After device validation, `engine` and `planner` can be narrowed to read-only/internal surfaces if Xcode call sites show no legitimate production mutation remains.
