# PhotoGuide UI / UX v0.3

## Product tone

目标不是“专业相机参数面板”，而是一个安静的现场摄影教练。

设计原则：

- 相机画面永远是主角。
- 一次只给一个主动作。
- 低信息密度。
- 不显示 86.7 这种伪精确摄影分数。
- 不用红色错误轰炸用户。
- 用户永远能按快门。
- 控制权通过“满意 / 换一个 / 做不到 / 取消 / Lock / Skip”体现。

## Visual language

- 深色 canvas。
- 白色正文。
- Mint accent 表示 READY / confirmed。
- Amber 只用于安全提醒或受限状态。
- `ultraThinMaterial` 做轻玻璃层。
- 26–28pt continuous corner radius 用于主要卡片。
- SF Symbols，不依赖占位图片资源。

## Home

首页先回答两个问题：

1. 这是干什么的？
2. 我现在能怎么开始？

因此首屏包含：

- PhotoGuide identity
- 一句价值主张
- Featured Recipe
- “开始实时指导”主入口
- 三个能力小标签

## Camera

层级从上到下：

1. 返回 / Recipe / Camera controls
2. lens selector
3. camera preview + subject / anchor overlays
4. contextual anchor prompt
5. single guidance card
6. action feedback controls
7. shutter + 满意 + 控制

## Shutter

快门始终 enabled。

READY 只改变快门环和指导状态，不改变拍照权限。

## Guidance card

主卡只包含：

- 一个 symbol
- 一句动作
- 一句原因/约束
- 关键 Goal 进度

动作执行中不展示新的动作。

## Safety

任何 context-dependent 移动会带一句轻量安全提示，例如：

> 先确认脚下和身后安全。

不使用恐吓式弹窗。


## v0.4.3 camera refinement

- Active guidance may use the full coach card; passive states collapse into a compact status surface. Do not keep a large card on screen when the user only needs to hold, wait, or shoot.
- The Recipe control is geometrically centered, not balanced by flexible spacers.
- Pinch is the primary continuous zoom gesture. Lens pills remain fast discrete shortcuts.
- During direct manipulation, show only the live zoom value; hide extra explanatory chrome.
- Optical changes invalidate stale semantic work but are not scene-identity changes.
- Respect Reduce Motion for repeating READY pulses and shutter feedback.
