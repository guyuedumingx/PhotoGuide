# PhotoGuide Multimodal Critic Contract v0.8

This is the stable network boundary for DJev and future low-latency multimodal/System-1/JEV-style photography models.

## Request

`POST` JSON to the configured HTTPS endpoint.

```json
{
  "contractVersion": 1,
  "frameID": 1280,
  "sceneRevision": 3,
  "bindingVersion": 7,
  "recipeID": "official.food",
  "locale": "zh-Hans-CN",
  "critic": {
    "intent": "Make the food look appetizing, intentional and visually clean.",
    "adviceStyle": "Give exactly one concrete, high-impact adjustment at a time.",
    "preferredSampleCount": 3,
    "minimumSampleSpacing": 0.22,
    "dimensions": [
      {
        "id": "composition",
        "name": "Composition",
        "rubric": "Judge crop, plate placement, negative space, tabletop balance and visual hierarchy.",
        "weight": 1.0,
        "targetScore": 0.82,
        "actionability": 1.0,
        "requiredForReady": true,
        "minimumConfidence": 0.55
      }
    ]
  },
  "slots": [],
  "frames": [
    {
      "frameID": 1271,
      "timestamp": 1790000000.10,
      "imageBase64": "..."
    },
    {
      "frameID": 1280,
      "timestamp": 1790000000.68,
      "imageBase64": "..."
    }
  ],
  "imageBase64": "..."
}
```

`imageBase64` is a temporary compatibility field containing the newest sample. New servers should use `frames`.

`slots` is also compatibility/support data for older Goal observations. The professional product path must not require it.


## Contract version

`contractVersion=1` identifies the stable semantic boundary. Additive fields remain on the same version; only breaking request/response semantics require a new version. Backends should ignore unknown additive fields.

## Response

```json
{
  "frameID": 1280,
  "sceneRevision": 3,
  "bindingVersion": 7,
  "observations": [],
  "critique": {
    "assessments": [
      {
        "dimensionID": "composition",
        "score": 0.61,
        "confidence": 0.92,
        "rationale": "The plate is centered but the empty lower-left area weakens the visual hierarchy.",
        "evidenceFrameIDs": [1271, 1280]
      },
      {
        "dimensionID": "food_presentation",
        "score": 0.79,
        "confidence": 0.88,
        "rationale": "The hero food reads clearly and texture is visible.",
        "evidenceFrameIDs": [1280]
      }
    ],
    "advice": [
      {
        "dimensionID": "composition",
        "kind": "composition",
        "title": "Move a little closer",
        "detail": "Trim the empty lower-left area while keeping the full plate edge visible.",
        "confidence": 0.90,
        "requiresPhysicalMovement": true
      }
    ],
    "overallScore": 0.72,
    "captureReady": false,
    "modelID": "djev-spark-2026-09"
  }
}
```

## Required semantics

- `score` and `confidence`: `0...1`.
- `requiredForReady=true` means that dimension must be confidently assessed and meet its Recipe target before the client can show READY.
- `minimumConfidence` is the per-dimension confidence floor for READY/coverage.
- Assess only dimensions requested in `critic.dimensions`.
- Do not invent off-frame objects or facts.
- Advice must be specific to visible evidence.
- Prefer one high-impact suggestion over a list.
- `captureReady=true` means the current image is already acceptable for this Recipe, not mathematically perfect.
- Set `requiresPhysicalMovement=true` for advice requiring photographer/subject movement.
- Keep rationale concise; it is diagnostic evidence, not a long essay.

## Advice kinds

Allowed client values:

- `composition`
- `camera`
- `lighting`
- `subject`
- `scene`
- `timing`
- `wait`
- `capture`
- `other`

## Compatibility and validation

The client validates:

- scene revision;
- binding version;
- result age;
- requested dimension IDs;
- duplicate/missing assessment dimensions;
- minimum dimension coverage.

Unknown dimensions are ignored. A response with insufficient dimension coverage is rejected rather than silently presented as a complete professional review.

## Model independence

The endpoint may be backed by DJev, another visual System-1 model, a JEV/JV-family model, or a future on-device multimodal evaluator. The app contract remains unchanged.
