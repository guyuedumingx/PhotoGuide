# PhotoGuide Recipe Question Contract v0.9

## 1. Scope

This is the canonical runtime contract for new PhotoGuide Recipes.

A Recipe does not describe actions. It describes **how to compare the current camera frame with one or more author-selected reference images**. The visual model is a bounded System-1 judge. It answers exactly one Recipe question at a time.

```text
current frame + references + one question
                 ↓
               DJev
                 ↓
       choice | score | boolean
                 ↓
      Recipe issue mapping
                 ↓
  one highest-priority issue in UI
```

The core must not generate movement instructions, camera-setting instructions, rationale, plans, or free-form advice.

## 2. Recipe runtime payload

A new Recipe needs only two intelligence-bearing assets:

1. `references[]`: one or more portable reference images.
2. `questions[]`: bounded comparison questions.

Other Recipe metadata (title, author, tags, market metadata, artwork) is product metadata and is not part of the judge contract.

### Reference

```json
{
  "id": "food-reference-1",
  "mimeType": "image/jpeg",
  "imageBase64": "..."
}
```

v0.9 embeds small reference-image bytes so imported/market Recipes are self-contained. A later package format may store the bytes as files without changing `VisualReference` at runtime.

## 3. Question types

Every question has:

- `id`
- `title`
- `prompt`
- `type`: `choice | score | boolean`
- `priority`: `0...1`
- a bounded answer specification
- Recipe-authored issue text for every reachable mismatch state

### Choice

```json
{
  "id": "angle",
  "title": "拍摄视角",
  "prompt": "当前拍摄视角与参考图相比？",
  "type": "choice",
  "priority": 1.0,
  "choices": [
    {"id":"too_high","label":"太高","issue":"拍摄角度比参考图偏高","severity":0.9},
    {"id":"matched","label":"接近参考图"},
    {"id":"too_low","label":"太低","issue":"拍摄角度比参考图偏低","severity":0.9}
  ]
}
```

An option with no `issue` is a target/matched answer. Choice values outside the declared option set are invalid and must never be interpreted as matched.

### Score

```json
{
  "id": "overall_similarity",
  "title": "整体相似度",
  "prompt": "当前画面与参考图整体视觉效果的相似度是多少？",
  "type": "score",
  "priority": 0.65,
  "scoreMin": 0,
  "scoreMax": 100,
  "expectedMin": 82,
  "expectedMax": 100,
  "belowIssue": "当前画面与参考风格还有明显差距"
}
```

A score outside the declared range is invalid. Every reachable mismatch side must have issue text.

### Boolean

```json
{
  "id": "background_clean",
  "title": "背景",
  "prompt": "当前背景的干净程度是否接近参考图？",
  "type": "boolean",
  "priority": 0.7,
  "expectedBoolean": true,
  "mismatchIssue": "背景与参考图的干净程度有差距"
}
```

## 4. Judge contract

The model interface is intentionally tiny:

```swift
public protocol VisualJudge: Sendable {
  func judge(_ request: VisualJudgeRequest) async throws -> JudgeAnswer
}

public enum JudgeAnswer {
  case choice(String)
  case score(Double)
  case boolean(Bool)
}
```

A request contains:

- encoded current frame
- Recipe references
- exactly one `VisualQuestion`
- locale
- frame id

It does **not** contain an action graph, goal graph, planner state, generated hint, or free-form response slot.

## 5. Runtime question management

`QuestionRuntime` owns only state management:

- `pending`: not yet judged or invalid response received
- `issue`: latest valid answer differs from Recipe target
- `matched`: latest valid answer matches target
- `skipped`: user has disabled the question for the current runtime session

### Skip / restore

- Skipped questions are excluded from judge scheduling and issue ranking.
- A user can restore one question or all skipped questions.
- Restore clears the stale answer so the question is judged again.
- Optical/camera-context invalidation clears answers but preserves current skips.

### Recheck

A matched result is not permanent. Current implementation uses a lightweight refresh policy:

- current issue: approximately 0.9 s refresh target
- matched: approximately 2.8 s refresh target

The coordinator still enforces a global request cadence. These are scheduling constants, not Recipe semantics, and can be tuned without changing the Recipe schema.

### Issue priority

The UI has one problem slot. For currently failing questions:

```text
issuePriority = recipeQuestion.priority × mismatchSeverity
```

This is not planning. It only selects which already-observed mismatch to show first.

- Choice severity is declared by the Recipe option (default 1).
- Boolean mismatch severity is 1.
- Score severity is the normalized distance from the accepted score range, with a small non-zero floor.
- Ties prefer the more recently evaluated issue.

## 6. UI contract

For the v0.9 question path:

- display the Recipe-authored issue text;
- optionally display the question title as context;
- allow skip of the current issue;
- expose a management sheet with pending / issue / matched / skipped state;
- allow restore of skipped questions;
- do not synthesize an action.

Example:

```text
拍摄角度比参考图偏高
拍摄视角
[跳过]
```

Not part of core:

```text
把手机拿低一点
向左移动
切换到 2×
把 ISO 调到 200
```

A future Recipe extension may carry an author-written hint. Such a field must remain optional and must not be required by `VisualJudge`, `QuestionRuntime`, priority calculation, or Recipe validity.

## 7. Recipe authoring

v0.9 authoring supports:

- start from a reference image;
- add/remove reference images;
- add/remove questions;
- select `choice / score / boolean`;
- edit prompt and mismatch issue text;
- set base priority;
- save locally;
- favorite;
- import JSON.

The current reference-image generator does not claim to infer a photographer's method. Until DJev is connected it creates a valid Recipe shell using the selected image plus generic starter questions. Real automatic Recipe extraction is a separate DJev integration task.

## 8. Compatibility

Old v0.8 Recipes may still contain semantic critic dimensions, Goal/Action data and no reference image. They remain readable for migration/compatibility, but they are not evidence of compliance with this v0.9 contract.

A new/custom/imported Recipe must contain at least one valid reference and one valid bounded question to enter the new question runtime.

## 9. Empirical validation still required

Structural tests cannot establish visual-judgment quality. After real DJev integration, evaluate on held-out current-frame/reference pairs:

- answer agreement with human labels per question;
- malformed/invalid-output rate;
- single-reference vs multi-reference consistency;
- issue-priority usefulness;
- recheck stability under camera motion;
- Recipe-specific questions vs generic starter questions.

No v0.9 artifact should claim those results before the benchmark is actually run.
