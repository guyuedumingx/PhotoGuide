# PhotoGuide v0.3.2 Core Hardening

本轮只修改可执行控制核心，不扩产品页面。

## Joint / Trade-off Goal Groups

新增 GoalGroup 组合层；它不是第七个 Primitive，而是由 Goal 组成的 Recipe 级结构。

- `joint`：多个 Goal 共同定义一个联合质量面，采用非补偿式 generalized mean。
- `tradeoff`：允许两个或多个有天然竞争关系的 Goal 在一块效用面上平衡，显式惩罚过大 spread。
- Scheduler 对组内最弱 Goal 提升优先级，并在明显失衡时降低已较强 Goal 的继续优化优先级。
- Readiness 对组内成员按 group utility 判定，不再错误要求每个成员分别跨越相同 floor。
- HARD Goal 仍保持独立 guard，不会因为 Goal Group 被补偿掉。

## Static Recipe Simulation

新增 `RecipeSimulationAnalyzer`。它不声称模拟真实物理世界，而是验证 Recipe 自己声明的 Action Effect 是否自洽：

1. 从抽象低质量状态出发；
2. 按 dependency 激活关键 Goal；
3. 只使用非 restricted Action；
4. 应用 expected improvement / possible damage；
5. 检查在有限步数内能否达到 HARD/CORE 最低可用状态。

Validator 对无法收敛的 Recipe 给出 `simulationCannotConverge` warning，避免明显坏 Recipe 进入运行时后才暴露死循环。

## Validator

新增：

- duplicateGoalGroupID
- missingGoalGroupMember
- duplicateGoalGroupMember
- invalidGoalGroupConfiguration
- overlappingCriticalGoalGroups
- simulationCannotConverge

关键 Goal 不允许同时出现在多个独立 Goal Group 中，避免重复计权和冲突优化。

## Tests

GuidanceCore：64 tests / 0 failures。

新增覆盖：

- Trade-off 失衡惩罚与恢复
- Planner 偏向弱成员
- Trade-off-aware Readiness
- Goal Group 结构校验
- Action Effect 声明无法收敛的静态模拟

RecipeKit：5 tests / 0 failures。
