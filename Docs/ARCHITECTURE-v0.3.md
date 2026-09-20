# PhotoGuide Architecture v0.3

## 1. Kernel invariants

1. 用户意愿高于优化器。
2. `UNKNOWN != UNSATISFIED`。
3. 已满足 Goal 允许后续 drift。
4. 系统追求 Best Reachable State，而不是理论 Ideal State。
5. Safety 是 veto，不进入可加权 trade-off。
6. UI 不拥有控制语义。
7. Evaluator 不直接产生动作。

## 2. Core primitives

### Node
场景参与者或结构：Entity / Region / Surface / Text / Geometry 等。

### Dimension
“测量什么”，不含目标值和权重。

### Relation
Node 之间的有向或无向关系。

### Goal
Recipe 对某个 Dimension + Binding 的目标。

### Evaluator
产生 Observation 的可替换实现：Vision、DJev、Telemetry 等。

### Action
改变当前状态的候选干预。

## 3. Runtime flow

```text
Frame
 ↓
Tracking + Binding
 ↓
Evaluation Planner
 ↓
Local CV + optional DJev
 ↓
Observation
 ↓
Goal Engine
 ↓
Dependency propagation / drift
 ↓
Scheduler
 ↓
Action Planner
 ↓
Capability / lock / constraint / safety filter
 ↓
Action proposal
 ↓
Human response
 ↓
Action verification
 ↓
Replan
```

## 4. Goal semantics

Runtime State：

```text
INACTIVE
UNRESOLVED
ACTIVE
SATISFIED
DRIFTED
UNKNOWN
BLOCKED
```

User policy 与状态分离：

```text
NORMAL
LOCKED
DEPRIORITIZED
SKIPPED
```

HARD / CORE / SOFT：

- HARD：guard；不可由 SOFT 补偿。
- CORE：Recipe 方法的主要部分。
- SOFT：增强项，不阻塞 READY。

## 5. Readiness

Natural READY：

```text
all non-skipped HARD satisfied
AND
all non-skipped CORE satisfied
```

SOFT 不作为拍摄门槛。

用户可随时按快门，因此 CaptureState 是建议状态，不是拍摄权限。

## 6. Action utility

```text
U(a)
= weighted expected gain
- regression damage
- physical burden
- risk
- uncertainty
- decline penalty
- failure penalty
```

Goal gain 权重同时考虑：

- constraint class
- Recipe importance
- current severity
- user deprioritization

这使“一个动作同时改善多个关键 Goal”自然获得更高优先级，可覆盖大部分 root-cause clustering 的 MVP 需求。

## 7. Action verification

Action proposal 保存受益 Goal 的 baseline score。

新帧到来后：

```text
Δscore high positive  → IMPROVED
Δscore small positive → PARTIAL
≈ 0                    → NO_EFFECT
negative               → OPPOSITE_EFFECT
no comparable evidence → INCONCLUSIVE
```

结果进入 ControllerMemory，影响后续同一动作优先级。

## 8. Evaluation Planner

每个 tick 根据 Goal 状态形成：

- guard-fast slots
- focus slots
- watch slots

Dimension registry 决定可用 Evaluator。

DJev semantic slots 被批量输出，因此满足“一张当前图、一次 DJev、多维度判断”。

## 9. Recipe

当前 `environment_portrait.recipe.json` 包含：

- 2 Nodes
- 1 Relation
- 8 Goals
- dependency graph
- 17 concrete Actions
- capability constraints
- safety classes

Relation 不再通过字符串 `primary_anchor` 拆词猜测，而是显式注册并绑定。

## 10. Module boundaries

`GuidanceCore` 不 import SwiftUI / UIKit / Vision / AVFoundation。

`CameraRuntime` 只负责 camera + photo I/O。

`PerceptionRuntime` 把视觉结果转成结构化观测，不决定用户怎么动。

`RecipeKit` 负责编译 Recipe 到 Core objects。

`GuidanceUI` 负责呈现 Action 和用户交互。


## Adaptive evaluator reliability (v0.3.6)

Fusion uses two distinct confidence concepts:

1. **Observation confidence**: what the evaluator says about this specific frame.
2. **Evaluator reliability**: session-local evidence about how trustworthy that evaluator has been for this dimension.

`defaultReliability` in the registry is only a prior. The runtime calibrator updates `EvaluatorID × DimensionID` slowly from near-synchronous cross-evaluator agreement. Calibration never uses the fusion output as a teacher, never lets a source self-confirm, and never promotes one session's learned trust into the published Recipe.

Conflict arbitration occurs before Goal state transitions. Severe unresolved disagreement reduces fused confidence below the decision threshold so the Goal becomes `UNKNOWN`, allowing the Evidence/VOI layer to request more information instead of issuing a potentially wrong physical correction.
