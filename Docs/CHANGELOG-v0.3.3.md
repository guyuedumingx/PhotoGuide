# PhotoGuide v0.3.3

## Causal action graph

- Added `ActionEffectGraph` as a derived runtime index over declared Action effects.
- Supports reverse lookup from Goal to actions, shared-root-cause discovery, and touched-goal analysis.
- This remains derived data; it does not add a seventh domain primitive.

## Short-horizon action planning

- Added `ActionPlanDefinition` / `ActionPlanRuntime` as runtime composition of existing Actions.
- Added `ActionSequencePlanner` with bounded beam search (`maxDepth` default 3).
- Planning remains anchored to the ordinary Scheduler's first action so HARD preemption, safety, capability, user constraints and locks cannot be bypassed.
- When the single-step controller reports unreachable only because a CORE move is temporarily costly, a short plan may rescue it if no HARD guard is failing.
- Plans account for session-learned action effectiveness, failure/decline penalties, action costs and interaction burden.

## Multi-step transaction semantics

- Every plan step is independently verified from fresh Observation evidence before advancing.
- Successful/partial verification advances; no-effect/opposite/inconclusive terminates the plan.
- Cancel, another-way, impossible, lock, skip and user-satisfied terminate the remaining plan without automatic rollback.
- New HARD regression preempts the remainder of a CORE plan.
- HARD and locked goals cannot be declared temporary regressions.
- Declared CORE/SOFT regressions can be tolerated between steps when later steps repair them.

## Verification

- GuidanceCore: 70 tests, 0 failures.
- RecipeKit: 5 tests, 0 failures.
- All Swift sources pass `swiftc -parse` in the current Linux environment.
- iOS framework linking/type-checking still requires macOS + Xcode before device validation.
