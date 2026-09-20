# PhotoGuide v0.4.4 — Internationalization + premium motion

PhotoGuide 是一个原生 iPhone 实时摄影指导应用。当前版本从 `guyuedumingx/PhotoGuide` 的 `0d8840d`（Codex MVP v0.2）演化而来，目标不再是“能打开相机”，而是把产品核心、控制逻辑和 UI 一次收敛到可真机验证的状态。


## v0.4.4 Internationalization + premium motion

这一版不改 Core 控制语义，集中把 iPhone 产品层补齐到可持续维护的国际化和统一动效体系：

- GuidanceUI 的用户可见文案全部通过 framework-localized bundle 获取，当前完整支持 English / 简体中文 / 繁體中文。
- 210 个 UI key 在三种语言中全覆盖；Camera / Photo Library 权限文案也通过 `InfoPlist.strings` 本地化。
- 默认开发/回退语言为 English，并自动跟随 iOS 系统或“每 App 语言”，不维护第二套语言状态。
- 英文和繁体文本扩展已反映到 Coach Card、Recipe 页面和 Camera Control Sheet 的自适应布局。
- 新增 `scripts/validate-localization.py`，检查漏翻、孤儿 key、重复 key、未包裹中文 Swift literal、英文 value 残留中文以及隐私权限本地化；当前为 `210 keys × 3 locales` 全通过。
- 新增统一 `PGMotion` / `PGPressButtonStyle` / `pgReveal` 动效语言：微交互、状态切换、settle、导航 reveal、READY breathing 均使用低幅度参数。
- Recipe 分类和 Lens Selector 使用 matched geometry selection；Camera Coach、提示、结果页采用克制的 opacity / tiny-scale 过渡。
- Vision 高频 tracking 禁止隐式 Core Animation，只有 focus / anchor / 新 direction cue 做一次性短动效，避免叠影和跟手延迟。
- 所有非必要 SwiftUI 动效尊重 Reduce Motion。
- UI 测试改用稳定 accessibility identifier，不再依赖中文按钮文案，并新增 English launch/navigation contract。

自动验证保持：`GuidanceCore 128/128`、`RecipeKit 6/6`、`Localization 210 × 3`。Linux 环境无法替代 Xcode 的 iOS SDK type-check、模拟器 UI tests 与真机动效验收。

见 `Docs/CHANGELOG-v0.4.4.md` 与 `Docs/INTERNATIONALIZATION-AND-MOTION-v0.4.4.md`。


## v0.4.3 Camera polish + direct manipulation

这一版继续收敛真机相机体验，重点是让界面更轻、相机操作更像一个完成度高的 iOS 产品：

- 指导面板改成两级形态：真正有动作时显示完整 Coach Card；READY / WAIT / UNKNOWN / 用户暂停时自动收成 72pt 轻量状态卡，把更多画面还给取景。
- 顶栏改为真正几何居中，Recipe 胶囊不会再被右侧闪光灯/网格按钮挤偏。
- 原生相机预览新增双指连续变焦；手势期间只显示一个小焦段读数，结束后回到正常界面。
- 焦段按钮和手势变焦都不再错误递增 `sceneRevision`；它们会取消旧 semantic 请求并短暂抑制新 DJev 请求，避免变焦过渡帧污染语义判断。
- 当当前 Action 本来就是“切换焦段”时，用户直接点镜头倍率或双指完成对应变焦，会自动进入 Action verification，不需要再多点一次“完成调整”。
- CameraRuntime 的 frame telemetry 现在读取设备**实际** `videoZoomFactor`，不再在 ramp 尚未完成时把目标倍率冒充真实倍率。
- 静态照片捕获明确使用 `.quality` prioritization。
- 人物角标、背景锚点、方向箭头进一步减细；背景锚点由实心点改为轻量圆环。
- 快门加入克制的瞬时取景闪白、保存状态缩放，并尊重“减少动态效果”辅助功能。
- 关键相机控件新增稳定 accessibility identifier，便于后续 Xcode UI regression。

见 `Docs/CHANGELOG-v0.4.3.md`。

## v0.4.2 Camera interaction refinement

这一版继续直接收敛 iPhone 产品层，不增加新的控制抽象：

- 主相机页不再重复显示“背景主体提示卡 + 指导卡”。当需要背景锚点时，唯一主卡直接进入点选模式。
- ActionPresenter 现在输出结构化 `previewCue / compositionGuide / safety`，UI 不再通过中文文案里有没有“左/右”来猜辅助线和安全提示。
- Vision 人物框附近会显示轻量方向箭头；三分线只在对应构图动作出现。
- 首次点画面用于选择背景主体；背景已经选定以后，普通点按只做对焦，不会意外改掉背景锚点。重新选背景放进拍摄控制面板。
- 相机预览新增原生对焦框反馈。
- 原来的系统 `confirmationDialog` 改成统一深色控制面板，包含满意/恢复指导、锁定、跳过、重新选背景、网格和重置。
- CameraRuntime 新增真实曝光补偿 API、能力范围和 `ISO / shutter / EV` 遥测；控制面板可调曝光补偿，但仍由系统自动曝光决定 ISO 与快门。
- 焦段、对焦、拍摄、READY 等关键交互补充轻触反馈；状态提示以短暂小胶囊出现，不再长期占据画面。
- CameraRuntime 顺手移除一次重复的 connection configuration 调用。

Core host boundary 保持 v0.3.9 freeze 约束不变。GuidanceCore / RecipeKit 控制逻辑没有为 UI 特效绕路。

见 `Docs/CHANGELOG-v0.4.2.md`。

## v0.3.9 新增：Core API Freeze / Failure-path Audit

v0.3.9 不继续扩张摄影抽象，重点清理真机前最危险的生命周期、同帧顺序和重放一致性问题。

- iOS 本地感知结果按**一个 processed frame 一个 `ingestBatch`** 原子进入 Core，避免验证超时在同一物理帧的不同 Dimension 之间抢跑。
- 新增 processed-frame clock API：只有“感知已经处理、但没有任何 usable observation”的帧才使用 `advanceFrame`。
- `满意 / 跳过 / 换一个 / 做不到 / Lock` 会正确终止或清理相关 Transaction / verification 状态，不再留下永久 `WAIT` latch。
- Replay 现在覆盖 capability、安全许可、空 processed frame、checkpoint restore、scene-condition reset 等此前可能隐藏在运行时的输入。
- `GuidanceSnapshot` 与 Runtime invariants 扩展到 Action / Plan / verification / capability / constraint / safety 状态，用于真机失败路径审计。
- Checkpoint 升级为 schema v2：Recipe 签名同时包含 Node / Relation / Dimension / Evaluator Registry contract；v1 可迁移，但会清洗旧 evaluator reliability。
- 清理 Action Planner / Stabilizer / Recipe fallback 中可避免的强制解包和 `try!`。

当前自动验证：`GuidanceCore 128/128`、`RecipeKit 6/6`。iOS Framework 仍需在 macOS/Xcode 上完成 linker 与真机验证。Core host contract 见 `Docs/CORE-API-FREEZE-v0.3.9.md`。

## v0.3.8 新增：Fault Containment / Runtime Budget / Checkpoint Recovery

这一版开始收口 Core API，不再继续堆新的摄影概念，重点解决真机阶段的运行可靠性。

- `EvaluatorHealthMonitor` 为每个 Evaluator 提供 frame-based circuit breaker：连续 timeout / transport / invalid output 会从 `degraded` 进入 `open`，冷却后才允许 probe；一次成功 probe 恢复。
- `EvaluationCoordinator` 现在同时负责 cadence、Evaluator health 和 runtime budget。DJev 挂掉时不会每 0.45 秒继续打失败请求，本地 Vision 继续工作。
- `RuntimeResourcePressure` 将运行资源分成 `nominal / constrained / critical`。非关键 Focus/Watch 工作先被降频或裁剪，HARD guard 不会因为省电被静默丢掉。
- iOS host 会把 `ProcessInfo.thermalState` 映射到 Core 的 resource pressure，过热时自动减少 semantic workload。
- `pauseRuntime / resumeRuntime` 正式定义后台、Camera/input pipeline 中断语义：中断时终止未完成 Transaction；恢复后旧场景证据全部失效，必须重新观察，不能用后台前的 READY 直接继续。
- `GuidanceSessionCheckpoint` 可以 JSON 序列化。它保存 Session constraint、Goal lock/skip policy、Effect Model 和 Evaluator Reliability，但不会保存 Safety Clearance、硬件 capability、旧 Observation、正在执行的 Action/Plan。
- Checkpoint 使用**完整 Recipe 结构签名**而不是只比 ID；Goal target、dependency、Action effect/safety 或 Goal Group 有变化都会拒绝旧 checkpoint。
- iOS 新增 30 分钟 TTL 的原子 checkpoint store，后台被系统杀掉后重新进入同一拍摄任务可以恢复用户约束和 Session 学习，但仍要求重新看当前画面。

当前自动验证：`GuidanceCore 114/114`、`RecipeKit 6/6`。iOS Framework 仍需在 macOS/Xcode 上完成 linker 与真机验证。

## v0.3.7 新增：Scene Condition Awareness

这一版开始，Controller 不再只根据历史表现判断某个 Evaluator 是否可信，还会显式考虑当前感知条件：低照度、逆光、运动模糊、主体过小、遮挡、多人拥挤、输入压缩和相机运动。

- `SceneConditionProfile` 是 Runtime sensing context，不是新的摄影 Goal，也不是第七个 Primitive。
- `SceneConditionReliabilityAdjuster` 会对不同 `EvaluatorKind × Dimension` 施加临时可靠性修正。
- 临时场景惩罚不会写回 session-learned reliability，避免一次逆光或抖动永久“判死”模型。
- 已知恶劣条件下的跨模型冲突会降低 reliability 学习速度，避免把环境问题误学成模型长期缺陷。
- 单一 Evaluator 的 Observation 现在也会被 reliability 调整绝对 confidence；以前 trust 只影响多模型之间的相对权重，这是一个已修复的核心漏洞。
- `GuidanceReplay`、`GuidanceSnapshot` 和 Session trace 会记录 scene conditions，真机问题可以确定性复现。
- `PerceptionRuntime` 增加轻量 BGRA frame sampling，用于估计低照度、逆光、运动/低细节风险，并结合主体大小、裁切、多人和 tracking motion 生成 scene profile。

当前自动验证：`GuidanceCore 105/105`、`RecipeKit 6/6`。iOS Framework 仍需在 macOS/Xcode 上完成 linker 与真机验证。

## v0.3 的核心闭环

```text
Recipe
  ↓
AVFoundation Camera
  ↓
Vision / local perception
  ↓
Observation
  ↓
Goal Engine + Dependency Graph
  ↓
Evaluation Planner
  ↓
Scheduler
  ↓
Semantic Action Protocol
  ↓
用户执行 / 换一个 / 做不到 / 取消 / 锁定 / 跳过 / 满意
  ↓
Action Verification
  ↓
Replan
  ↓
READY / READY_BY_USER / PAUSED / UNREACHABLE
```

## 这版重新做了什么

### 1. Core 不再是 UI 字符串驱动

六个核心 Primitive 已真正进入代码：

- `Node`
- `Dimension`
- `Relation`
- `Goal`
- `Evaluator`
- `Action`

Action 不再是 `guide.person_scale.primary` 这种没有语义的 ID。现在 Action 明确包含：

- actor
- operation
- direction
- magnitude
- coordinate frame
- condition
- effect model
- burden / risk / uncertainty
- capability requirement
- safety class

UI 只负责把 Action 翻译成人能理解的话，不再决定控制逻辑。

### 2. 修正 Goal FSM 和 READY 逻辑

- 初次可靠观测不会卡在 `UNRESOLVED`。
- Hysteresis 只保护已经稳定的 Goal。
- `UNKNOWN` 不等于失败。
- Dependency 会让下游 Goal 在上游未满足时保持 `INACTIVE`。
- SOFT Goal 不再阻止 READY。
- HARD Goal 默认不可跳过。
- 用户说“满意”不会覆盖失败的 HARD guard。

### 3. Action 真正可验证

“完成”现在不是直接把动作标记为成功。

系统会保存执行前 Goal score，在新帧到来后比较：

- improved
- partial
- no effect
- opposite effect
- inconclusive

连续反向/失败会降低该 Action 的优先级，避免机械重复。Session-local Effect Model 会根据 improved / partial / no-effect / opposite-effect 结果校准动作有效性，但不会修改已发布 Recipe。

### 4. Human-governed

- 快门始终可按，不再用算法锁住拍照权。
- “换一个”只拒绝当前办法。
- “做不到”把动作 family 加入当前 Session constraint。
- “取消”从当前位置重新观察，不自动 rollback。
- Lock 会阻止后续 Action 破坏用户喜欢的状态。
- Skip 只允许非 HARD Goal，并降低 Recipe conformance。
- 连续调整过多时 Scheduler 会暂停主动打扰。
- 左/右、前/后等 ABAB 往返动作会被识别为 oscillation，停止 ping-pong。
- UNKNOWN 现在输出显式 `EvidenceRequest`，不会被当成“照片很差”直接纠正。
- Runtime Reachability 会基于设备 capability、用户约束、Lock 与安全许可区分“未知”和“当前不可达”。
- `Joint / Trade-off Goal Group` 已进入内核：相关 Goal 不再被错误地当成彼此独立 KPI，弱项会获得优先级，强项在失衡时会被抑制，从而减少 ping-pong。
- Readiness 可以按联合/权衡效用面判断，而不是要求每个成员都达到相同的独立 floor。
- Recipe Validator 新增 Goal Group 结构检查与抽象动作收敛模拟，可提前发现重叠关键组、缺失成员和声明的 Action Effect 无法把 Recipe 推向可用状态的问题。

### 5. Camera Runtime 修正

- 优先使用虚拟多摄设备（Triple / Dual Wide / Dual）。
- 支持动态焦段能力和 1× / 2× 等 zoom control。
- Action Planner 会根据设备 capability 过滤不可执行动作。
- 对焦点通过 `AVCaptureVideoPreviewLayer` 做坐标转换，不再直接把 SwiftUI 视图坐标塞给设备。
- Vision overlay 也通过 preview layer 做画面坐标映射。

### 6. Perception Runtime

- Vision 人体框、位置、比例、完整性、Body Pose。
- 短时遮挡保持 primary subject，不立即静默换人。
- 真正重新绑定人物时递增 `bindingVersion`，旧语义结果自动失效。
- 人体框做时间平滑。
- 背景主体由用户点选 + Vision saliency 辅助。
- 本地 relation heuristic 保留为 fallback，不冒充语义模型。

### 7. DJev 接口已打通到工程边界

如果 Debug Scheme 提供：

```bash
DJEV_ENDPOINT=https://your-endpoint.example/evaluate
DJEV_TOKEN=...
```

App 会：

1. 根据 active Goal Graph 生成 semantic slots。
2. 一张当前图片打包所有需要 DJev 判断的维度。
3. 约 2 Hz rate limit。
4. 用 `frameID + bindingVersion + sceneRevision` 拒绝过期结果。
5. DJev 不可用时继续使用本地 CV，不产生假语义结果。

> 生产环境不要把长期密钥直接放进 App。建议用你自己的轻量代理服务签名/转发。

## v0.3.3：因果 Action Graph 与短视野多步规划

- `ActionEffectGraph`：从 Action 声明中建立 Goal ↔ Action 因果索引，识别共享根因。
- `ActionSequencePlanner`：最多 3 步 beam-search，不做无限长计划，避免实时场景快速失效。
- 多步计划必须由单步 Scheduler 的安全/优先级判断锚定；只有在无 HARD failure 时，才允许多步方案从“单步不可取但整体可取”的 CORE trade-off 中救回。
- 每一步都必须完成真实 Observation verification 后才会进入下一步。
- HARD / LOCKED Goal 永远不能作为临时牺牲项。
- CORE / SOFT 可以在计划中出现声明过的临时回退，但必须由后续步骤修复。
- Cancel / Another Way / Impossible / Lock / Skip / User Satisfied 会终止整个未完成计划，不自动 rollback。
- 新 HARD regression 会立刻抢占原计划；系统可重新规划新的 guard-first 多步计划。
- 计划效用与单步 Action 使用同一量纲的 priority-weighted expected gain，并计入 burden / risk / uncertainty / learned failure penalties / interaction cost。


## v0.3.4 新增：信息价值（VOI）与计划级不确定性

- `InformationEffect` 进入 Action Protocol：HOLD / WAIT / SELECT_ANCHOR 不再是特殊分支，而是显式的信息获取 Action。
- `InformationPlanner` 会计算 Value of Information：当“先看清楚”比“马上纠正”更有价值时，Scheduler 会优先选择信息动作。
- 初始完全没有 Observation 时，不会错误地叫用户“保持一下”；只有已有但低置信度/脏证据时，HOLD / WAIT 才参与决策。
- Information Action 也要执行后验证：系统比较新旧 confidence / resolution，而不是默认认为等待一定有效。
- ActionInstance 记录 `verificationGoals`，只等待本次真正需要的新证据，避免一个批量信息动作因为无关 Goal 没更新而永久卡住。
- `PlanningUncertaintyModel` 对多步计划传播不确定性，并加入相关性下限，防止长计划因为简单独立假设看起来“虚假确定”。
- `ActionPlanDefinition` 现在同时记录 `expectedUtility / utilityUncertainty / confidenceAdjustedUtility`。
- `ActionSequencePlanner` 用 confidence-adjusted utility 排序；高收益但高不确定性的长链不会天然压过短、稳的方案。
- 信息动作不会被错误塞进质量优化的多步 Action Sequence；它们只通过 VOI 决策进入执行链。
- Recipe Validator 开始验证 information-effect 的 Goal 引用和重复声明。

控制器现在可以在两类选择之间直接比较：

```text
立即调整画面
vs
先获得更多信息
```

这让 `WAIT / HOLD / REOBSERVE` 从“异常状态处理”升级为正式的决策行为。


## v0.3.5 新增：可复现运行时 + 评估预算 + 固定 Tick Pipeline

- 新增 `GuidanceReplayEvent / GuidanceReplayer`：Observation、用户事件与 Tick 可以序列化并确定性回放，真机出现一次异常后可以离线完整重现 Controller 决策。
- Replay 会保留被拒绝的脏 Observation，因此 Validator / Registry 问题也可以复现，而不只复现“成功进入 Core”的数据。
- Replay buffer 有容量上限，避免长时间拍摄时调试日志无界增长。
- 新增 `EvaluationCoordinator`：把 `Guard / Focus / Watch` 真正映射为不同采样节奏。HARD guard 可高频持续检查，Focus 目标中频更新，已满足的 Watch 目标低频巡检。
- Action / dependency invalidation 可以立即打破 Watch 节流，相关 Goal 下一帧重新评估，避免为了省算力错过真实 regression。
- Local 与 Semantic evaluator 使用独立 cadence budget，为未来 Vision 高频 + DJev 低频/事件驱动调度提供稳定接口。
- 新增 `RuntimeTickPhase` 与 `tickDetailed()`：将 Controller 的安全关键阶段固定为 14 个可审计阶段，输出 work sets、最终 decision、readiness 与 invariant issues。
- `GuidanceRuntimeActor` 同步暴露 `tickDetailed()` 和 replay log，iOS Runtime 无需直接访问可变 Session。
- `UserEvent` 正式 `Codable + Equatable`，便于自动化重放和回归测试。

这轮的目标不是增加摄影功能，而是解决真机阶段最棘手的问题：**一次偶发错误必须可以被完整记录、离线重放、精确定位，同时不能因为每帧评估所有 Goal 导致 Vision / DJev 成本和热量失控。**

## v0.3.6 新增：Evaluator Reliability Learning + Conflict Arbitration

- 新增 `EvaluatorReliabilityModel`：Registry 的 `defaultReliability` 只作为先验，运行时会按 **Evaluator × Dimension** 学习当前 Session 中的有效可信度。
- 学习只来自同一 binding / scene 中的跨 Evaluator 近同步证据；单一 Evaluator 不能自我确认可信度。
- 相同证据对只训练一次，过旧的跨模型结果不会反复训练 reliability，避免高频 Vision 对低频 DJev 产生虚假强化。
- 可靠性是 Session-local，恢复和降权都使用慢速更新；不会把一次户外逆光失败永久写回 Recipe 或全局 Registry。
- 新增 `ObservationConflictArbitrator`，显式区分 `none / mild / severe` 模型冲突。
- 两个高置信度、相近可信度的 Evaluator 严重冲突时，Fusion 不再强行选一个答案，而是把融合 confidence 压低，使 Goal 进入 `UNKNOWN` / Evidence Request。
- 当历史证据已经证明某个 Evaluator 明显更可靠时，冲突允许由强来源主导，但仍保留冲突 confidence penalty。
- Continuous fusion 现在加入加权方差惩罚，不再只取均值而忽略来源之间的数值分歧。
- Session trace 会记录 evaluator conflict，`GuidanceSnapshot` 会导出每个 Evaluator/Dimension 的 learned reliability、sample count、conflict count 与 Goal conflict report。
- Replay 因为记录原始 Observation，因此 reliability 学习和冲突决策也能确定性重放。

这一层解决的是多模型真机环境中的核心问题：

```text
Vision: pose = MATCH
DJev:   pose = ABOVE
Temporal: 当前输出不稳定
        ↓
不再固定权重硬平均
        ↓
Session reliability + conflict arbitration
        ↓
可靠来源主导 / 或降为 UNKNOWN
```

## UI v0.3

UI 已重做为 camera-first 的深色玻璃态设计：

- 独立首页，不再启动就进入“工程 Demo 相机”。
- Featured Recipe 卡片。
- Edge-to-edge 相机。
- 单一主指导卡片。
- 大主操作 + 次级“换一个 / 做不到 / 取消”。
- 焦段胶囊选择器。
- 背景 Anchor 引导。
- READY 视觉反馈。
- “满意”和“控制”保留用户主动权。
- 拍摄结果页区分 Recipe conformance，而不是伪精确分数。

## 工程结构

```text
PhotoGuide/
├── PhotoGuideApp/
├── Packages/
│   ├── GuidanceCore/
│   ├── CameraRuntime/
│   ├── PerceptionRuntime/
│   ├── RecipeKit/
│   └── GuidanceUI/
├── Tests/
├── Docs/
├── project.yml
└── scripts/
```

## v0.4.4 验证基线

```bash
swift test --package-path Packages/GuidanceCore
# 128 tests, 0 failures

swift test --package-path Packages/RecipeKit
# 6 tests, 0 failures

./scripts/validate-localization.py
# 210 keys × 3 locales

xcodebuild -project PhotoGuide.xcodeproj -scheme PhotoGuideApp \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test CODE_SIGNING_ALLOWED=NO
# RecipeKitTests 3/3, PerceptionRuntimeTests 4/4, PhotoGuideUITests 4/4
```

此外，无签名的 generic iPhoneOS 构建已通过。相机权限、真实镜头、拍照保存、动作和触感仍需在 iOS 18+ 真机完成最终验收；DJev 保持可替换契约边界，本版本不包含真实 API 凭据。

## 在 Mac 上准备工程

```bash
cd PhotoGuide-evolved
./scripts/prepare-xcode.sh
```

脚本会检查 `xcodegen`、生成 `PhotoGuide.xcodeproj`，然后打开 Xcode。

也可以手工：

```bash
brew install xcodegen
xcodegen generate
open PhotoGuide.xcodeproj
```

先在 Simulator Build，再选 iPhone 18+ 真机运行。

详见：

- `Docs/ARCHITECTURE-v0.3.md`
- `Docs/CORE-API-FREEZE-v0.3.9.md`
- `Docs/DESIGN-SYSTEM.md`
- `Docs/DJEV-CONTRACT.md`
- `Docs/PRE-DEVICE-CHECKLIST.md`
- `Docs/CHANGELOG-v0.3.9.md`

## v0.4.0 UI product pass
The iPhone surface has been rebuilt around a quiet camera-first hierarchy: one instruction, one primary action, contextual overlays, compact controls, and a photo-first review screen. Core behavior remains behind the frozen GuidanceSession host boundary.

## v0.4.1 full product surface

The planned iPhone product flow is now implemented in SwiftUI instead of remaining a design spec:

- Home → Recipe Library → Recipe Detail → Camera Coach → Capture Review.
- Environment Portrait is live; upcoming recipes are clearly marked and not wired to fake logic.
- The camera UI uses a centered recipe control pill, contextual thirds guidance, subtle Vision corner guides, one primary action, compact lens controls, recent-photo thumbnail, and READY shutter feedback.
- Camera zoom actions can be applied by PhotoGuide itself and are still verified by the frozen GuidanceCore action loop. Human movement and pose instructions remain manual.
- Capture review keeps the photo dominant and uses qualitative Recipe conformance instead of synthetic scores.

See `Docs/CHANGELOG-v0.4.1.md`.
