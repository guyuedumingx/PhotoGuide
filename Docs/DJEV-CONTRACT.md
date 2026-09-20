# DJev semantic contract

DJev 在 PhotoGuide 中是 Evaluator，不是 Planner。

它只回答：

> 当前画面在这些 Dimension 上观察到什么？

它不回答：

> 用户下一步应该怎么做？

## Request semantics

单张当前 frame + 多个 semantic slots：

```json
{
  "frameID": 1832,
  "sceneRevision": 4,
  "bindingVersion": 2,
  "slots": [
    {
      "dimension": "std.pose.body_orientation",
      "binding": {"scope": "NODE", "id": "primary"}
    },
    {
      "dimension": "std.relation.visual_balance",
      "binding": {"scope": "RELATION", "id": "primary_anchor"}
    }
  ],
  "imageBase64": "..."
}
```

## Response semantics

```json
{
  "frameID": 1832,
  "sceneRevision": 4,
  "bindingVersion": 2,
  "observations": [
    {
      "dimension": "std.pose.body_orientation",
      "binding": {"scope": "NODE", "id": "primary"},
      "valueType": "ordinal",
      "ordinalValue": 1,
      "boolValue": null,
      "numberValue": null,
      "stringValue": null,
      "confidence": 0.83,
      "distribution": {"0": 0.28, "1": 0.62, "2": 0.10}
    }
  ]
}
```

## Freshness

结果只有在以下条件都满足时进入 GoalEngine：

- result frame 不是未来帧
- frame delta 在窗口内
- bindingVersion 相同
- sceneRevision 相同

否则直接丢弃。

## Failure behavior

DJev：

- timeout
- 5xx
- invalid response
- unavailable

均不会中断 Camera Runtime。

本地 Vision 继续运行，相关 semantic Goal 保持 UNKNOWN 或由 local fallback 提供低置信度观测。

## Runtime configuration

Debug 环境可用：

```text
DJEV_ENDPOINT
DJEV_TOKEN
```

未配置时不会上传任何图片。
