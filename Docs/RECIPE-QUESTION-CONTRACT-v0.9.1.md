# Recipe Question Contract v0.9.1

## Core

```text
Reference images + ordered questions[] + current frame
  -> VisualJudge
  -> choice | score | boolean
  -> Recipe-authored issue text
```

There is no question priority, mismatch severity, action mapping, advice generation, or planner in this contract. Array order is semantic.

## Question types

### Choice
A closed set of option IDs. An option with `issue = null` means it matches the Recipe target. Any other option carries only the problem text shown to the user.

### Score
A bounded numeric range plus an accepted range. Values below/above the accepted range map to Recipe-authored problem text.

### Boolean
A target boolean plus one mismatch problem string.

## Runtime order

1. Ignore questions explicitly skipped by the user.
2. Evaluate previously unseen active questions in `questions[]` order.
3. Recheck active questions periodically, still in `questions[]` order.
4. Keep current issues in `questions[]` order.
5. Camera UI shows those issues in a horizontal swipe surface. User selection never mutates Recipe order.
6. Skipping the selected card removes that question from evaluation until restored.

Recheck cadence is a resource policy only. It must never reorder questions or issues.

## Example

```json
{
  "references": [{"id":"ref.1","mimeType":"image/jpeg","imageBase64":"..."}],
  "questions": [
    {
      "id":"angle",
      "title":"拍摄视角",
      "prompt":"当前拍摄视角与参考图相比？",
      "type":"choice",
      "choices":[
        {"id":"too_high","label":"太高","issue":"拍摄角度比参考图偏高"},
        {"id":"matched","label":"接近参考图","issue":null},
        {"id":"too_low","label":"太低","issue":"拍摄角度比参考图偏低"}
      ]
    },
    {
      "id":"overall_similarity",
      "title":"整体相似度",
      "prompt":"当前画面与参考图整体视觉效果的相似度是多少？",
      "type":"score",
      "scoreMin":0,
      "scoreMax":100,
      "expectedMin":82,
      "expectedMax":100,
      "belowIssue":"当前画面与参考风格还有明显差距"
    }
  ]
}
```

## Authoring

Authors choose the order directly in Recipe Studio with move-up / move-down controls. That order is preserved in JSON import/export/storage and used by runtime without ranking.

## Deliberately outside core

- movement or camera-parameter instructions;
- generated advice;
- author hint extensions;
- free-form model explanations;
- automatic ranking of problems.

These may exist later as optional surfaces, but Recipe validity and VisualJudge must not depend on them.
