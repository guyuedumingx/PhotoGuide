# PhotoGuide v0.3.6

## Adaptive evaluator reliability

- Added `EvaluatorReliabilityModel`, keyed by evaluator and dimension.
- Registry reliability is now a prior rather than a permanently fixed fusion weight.
- Runtime reliability adapts slowly from near-synchronous cross-evaluator agreement.
- A single evaluator cannot self-confirm its own reliability.
- Identical evidence pairs are trained once; stale evaluator pairs outside the calibration window do not train reliability.
- Reliability remains session-local and can recover after later consistent evidence.

## Conflict-aware observation fusion

- Added `ObservationConflictArbitrator` and explicit none/mild/severe conflict reports.
- Severe disagreement between similarly trusted high-confidence evaluators collapses fused confidence instead of forcing a winner.
- A historically dominant reliable source may still lead a conflicting fusion, with a confidence penalty.
- Continuous fusion now applies weighted variance/dispersion penalties.
- GoalEngine stores the latest conflict report per goal.

## Auditability

- `GuidanceSnapshot` now exposes learned evaluator reliability and goal conflict reports.
- Session trace records evaluator conflicts with agreement and dominance diagnostics.
- Deterministic replay reproduces reliability learning because it replays raw observations.

## Verification

- GuidanceCore: 97 tests, 0 failures.
- RecipeKit: 6 tests, 0 failures.
- Added tests for severe conflict -> UNKNOWN, persistent outlier down-weighting, per-dimension isolation, recovery, learned fusion winner, duplicate-pair protection, stale-pair protection, and snapshot/trace diagnostics.
