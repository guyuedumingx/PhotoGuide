# MVP v0.2 验收边界

## 版本目标

让普通用户在一台 iOS 18+ iPhone 上，不理解 Goal、Dimension 或 Recipe，也能完成一次环境人像任务：打开相机、选择背景主体、跟随单条提示、处理无法执行的建议、达到 READY、拍照并保存。

## 已由自动化验证

- Recipe 资源真实解码，不走 fallback；包含 8 Goal 和 16 Action。
- 匹配观测连续到达后，完整 Recipe 能进入 READY/full conformance。
- Done 后必须等新帧再规划，不会立即重复同一建议。
- Another way、Impossible、Cancel、Lock、Skip 和 Looks good 不会让状态机死锁。
- HARD guard 失败时，“我满意了”不能绕过拍摄门槛。
- 本地构图算法能区分平衡、背景主体过小和人物缺失。
- 模拟器 UI 能从 2/8 逐项推进至 8/8、进入 READY，并只在 READY 后开放拍摄。
- 控制面板中的锁定、跳过和重新开始可以从 UI 访问。

## 已实现但只能在真机完成最终验收

- 相机授权、实时预览和竖屏方向。
- 前后摄像头、前摄镜像、闪光灯和点按对焦。
- Vision 人物框、姿态、显著性区域以及 8 Hz/2 Hz 分层计算。
- 拍照、Photos add-only 授权、相册保存与结果页。
- 后台/前台切换后的相机会话恢复。

## 明确未包含

- 真实 DJev API 或任何远端图像上传。
- Recipe 创建器、模板市场、社区和账号系统。
- 横屏、iPad、视频拍摄和系统相册编辑。

未包含项不阻挡单 Recipe 环境人像 MVP 的真机试用，但真机性能与场景准确率未完成前，不应称为生产发布版本。
