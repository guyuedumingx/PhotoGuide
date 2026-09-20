# v0.2 → v0.3

基线：`guyuedumingx/PhotoGuide@0d8840d`。

## Rebuilt

- GuidanceCore domain model
- Action protocol
- Goal FSM
- Scheduler readiness semantics
- Action verification
- Registry / Validator
- explicit Relation binding
- Evaluation Planner
- Camera capabilities / zoom
- preview coordinate conversion
- subject binding generation
- optional DJev HTTP adapter
- entire SwiftUI product shell

## Removed architectural shortcuts

- 不再从 Goal 反向伪造 Dimension Registry。
- 不再通过 `primary_anchor.split("_")` 猜 Relation。
- 不再让 UI 根据 Goal 数值决定 Action 语义。
- 不再要求 SOFT Goal 全满足才能 READY。
- 不再用 READY 锁住快门。
- 不再把“用户点完成”视为动作成功。
- 不再建议设备不具备的 2× 能力。

## Deliberately not added

- Recipe marketplace
- account system
- social/community
- multi-recipe creator UI
- video recording
- iPad

这些在第一轮真机闭环被证明确实有价值前都不会扩张。

## Core hardening 2026-09-20

- Added session-local `SessionEffectModel` with per-action/per-family EWMA calibration.
- Planner now learns repeated no-effect/opposite-effect outcomes without mutating Recipe definitions.
- Added shared-root-cause coverage bonus so one action that improves several active critical goals can beat multiple micro-actions.
- Added explicit `EvidenceRequest` decisions for unknown HARD/CORE goals.
- Added runtime `ReachabilityAnalyzer` under current capability, lock, safety and session constraints.
- Added motion oscillation detection for left/right, up/down, forward/backward and toward/away ABAB patterns.
- Scheduler pauses active guidance on repeated oscillation instead of ping-ponging the user.
- GuidanceCore regression suite expanded to 59 tests; RecipeKit remains 5/5.
