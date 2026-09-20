# PhotoGuide v0.3.7

## Scene-condition-aware perception reliability

- Added `SceneConditionProfile` for runtime sensing context: low light, backlight, motion blur, subject smallness, occlusion, multi-person crowding, input compression, and camera motion.
- Added `SceneConditionReliabilityAdjuster`, conditioned by evaluator kind and dimension semantics.
- Scene penalties are temporary and never mutate session-learned evaluator reliability.
- Reliability calibration reduces learning pressure when disagreement occurs under a known poor sensing context.
- Conflict arbitration now uses condition-resolved reliability.

## Single-source confidence correctness

- Fixed a core fusion defect where reliability only changed relative source weighting and could not lower the absolute confidence of a sole evaluator.
- Single-source observations now scale confidence using reliability/freshness before entering GoalEngine.
- Multi-source fused confidence now incorporates absolute trust instead of allowing trust to cancel algebraically.
- Severe scene conditions can therefore correctly push a semantic/control goal to `UNKNOWN` rather than accepting a high raw model confidence.

## On-device condition sensing hook

- `PerceptionRuntime.SceneObservation` now carries a `SceneConditionProfile`.
- Added a cheap BGRA sampling path for luminance, dark-pixel fraction, center-vs-border backlight signal and edge energy.
- Person scale, incomplete visibility/pose, human count and short-term tracking motion augment the frame profile.
- `GuidanceViewModel` forwards the profile into `GuidanceSession` before ingesting observations.

## Replay and auditability

- Added `GuidanceReplayEvent.sceneConditions`.
- `GuidanceSnapshot` exposes the active scene condition profile.
- Session trace records severe scene-condition diagnostics.
- Actor runtime exposes `updateSceneConditions`.

## Verification

- GuidanceCore: 105 tests, 0 failures.
- RecipeKit: 6 tests, 0 failures.
- All Swift source files pass syntax parsing in the current environment.
- iOS AVFoundation/Vision/SwiftUI linker and device verification remain Mac/Xcode-only.
