# Pre-device checklist

## A. 已完成的 Linux / Pure Swift 验证

- [x] GuidanceCore Swift 6 build
- [x] GuidanceCore 128 tests / 0 failures
- [x] RecipeKit Swift 6 build
- [x] RecipeKit 6 tests / 0 failures
- [x] Recipe JSON 编译与 Validator 通过
- [x] 所有 Swift 文件 `swiftc -parse`
- [x] Swift 6 formatter
- [x] UI 不用 Mock semantic 结果冒充真实模型
- [x] DJev 接口保持 optional；semantic 不可用时 Core 仍能运行 local goals
- [x] 同一 local processed frame 的 observations 通过一个 `ingestBatch` 原子提交
- [x] Replay 覆盖 capability / safety / checkpoint restore / scene-condition reset / empty processed frame
- [x] Checkpoint schema v2 覆盖 Registry contract，并保留受控 v1 migration
- [x] Runtime invariant audit 覆盖 Action / Plan / verification / pause / READY 生命周期

## B. 第一次到 Mac 上

```bash
./scripts/prepare-xcode.sh
```

然后执行：

```bash
xcodebuild \
  -project PhotoGuide.xcodeproj \
  -scheme PhotoGuideApp \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

如果 build 成功，再开 Simulator 做 UI smoke test。此阶段只修 Apple-framework 类型/链接/权限/actor-isolation 问题，不再扩 Core 抽象。

## C. 第一次真机：功能闭环

只验证这些，不扩功能：

1. 后置相机 1× 预览是否正常。
2. 人物 bbox 是否跟画面位置一致。
3. 点背景主体时 marker 与手指位置一致。
4. 点按是否在正确位置对焦。
5. 2× 按钮只在设备支持时出现；capability 变化能进入 replay/snapshot。
6. 多人物交叉时有没有突然换绑。
7. 同一 local frame 的多 Dimension 不会触发中途 verification timeout。
8. “完成”后是否等**新的 processed evidence**再给下一步。
9. “换一个”后当前验证状态立即结束，替代 action 可继续。
10. “做不到”后同 family 是否消失且不残留 WAIT。
11. “取消”后是否从当前位置重新观察，不做物理 rollback。
12. “跳过”当前 Goal 时，与该 Goal 绑定的 transaction 是否立即终止。
13. “锁住”后任何可能伤害该 Goal 的 transaction/plan 是否停止。
14. “满意”后是否立即停止 pending work；失败 HARD guard 仍不能被覆盖。
15. 未 READY 时快门是否仍可按。
16. 拍照与 add-only 相册保存是否正常。

## D. 故障与恢复

- [ ] App 在 Action proposed / verifying 时进入后台；回前台必须重新观察，不得恢复旧 READY。
- [ ] 后台被系统杀掉后 30 分钟内重新进入：locks/constraints/calibration 可恢复，但 safety clearance、capabilities、旧 observations、active transaction 不得恢复。
- [ ] 修改 Dimension/Evaluator Registry contract 而复用 Recipe ID，旧 schema-v2 checkpoint 必须拒绝。
- [ ] 用 schema-v1 checkpoint 恢复时，已不存在的 evaluator/dimension reliability 必须被清理。
- [ ] 连续模拟 DJev timeout；达到阈值后 semantic evaluator 被隔离，本地 Vision 继续工作。
- [ ] circuit-breaker cooldown 后只做受控 probe；probe 成功才恢复 semantic cadence。
- [ ] semantic 返回错误 Dimension / Binding / frame / scene revision 时必须被拒绝且可在 replay 中复现。
- [ ] scene condition 从 low-light/motion 恢复为 clear 后，replay 终态也必须是 clear，而不是残留旧 profile。
- [ ] Camera/perception pipeline 暂停时不得保留 pending Action/Plan/verification。
- [ ] thermal serious/critical 时 semantic workload 降低，但 HARD local guard 不得被节流掉。

## E. Replay / invariant 调试流程

真机出现“左右来回、突然换建议、一直等、后台回来状态不对”等问题时，优先导出：

1. `session.replayEvents`
2. `session.snapshot()`
3. `session.invariantIssues()`
4. Session trace

先在离线 `GuidanceReplayer` 重放，再修改 Scheduler/GoalEngine。不要直接根据 UI 表象猜 Core 原因。

## F. 性能记录

建议记录：

- preview FPS
- local Vision avg / p95 latency
- semantic request rate / p95 latency / timeout rate
- CPU / memory / thermal state
- 10 分钟电量变化
- action suggestions per minute
- action verification success/no-effect/opposite rate
- repeated advice / oscillation rate
- evaluator conflict-to-UNKNOWN rate

## G. 真机前不能伪造的结论

Linux 环境无法对 AVFoundation / Vision / SwiftUI 完成 Xcode 链接，因此 v0.3.9 当前状态定义为：

> **Pure-Swift core validated; ready for first Xcode/device integration pass**

而不是：

> production validated

真机阶段的目标首先是验证坐标系、并发/生命周期、传感器性能和真实控制体验，而不是再增加控制抽象。
