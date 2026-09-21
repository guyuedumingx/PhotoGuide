# PhotoGuide semantic kernel v0.8.1

The market product has one primary intelligence path:

```text
sampled camera frames
        ↓
CriticProfile from Recipe
        ↓
replaceable multimodal critic
(DJev / JEV / future System-1 visual model)
        ↓
multi-dimensional assessments
        ↓
SemanticCriticSession
        ↓
READY or one professional next action
```

`SemanticCriticSession` intentionally does **not** know whether the camera is viewing a person, flower, plate of food, pet, product, building or landscape. It only knows the Recipe quality dimensions and the model's assessments.

## Minimal state

The session stores only:

- one `CriticProfile`;
- the latest accepted `SemanticCritique`;
- acceptance timestamp;
- one temporarily held advice item;
- validation issues.

It does not own Vision, subject tracking, camera telemetry, Goal graphs, UI text, or Recipe categories.

## READY contract

A Recipe may mark important quality dimensions with:

- `requiredForReady=true`;
- `minimumConfidence`;
- `targetScore`.

A positive model READY hint cannot bypass these gates. This prevents a partial/malformed response from showing a false READY state while still leaving the photographic judgment itself with the multimodal model.

## Local Vision boundary

Local Vision is optional support:

- overlays;
- focus/telemetry;
- degraded offline hints;
- compatibility observations.

Critic requests are sampled directly from the camera stream and are not gated by local person/object tracking. Whole-image critique freshness also ignores local binding-version changes.

## Release gate

Structural ablation requires `critic-only` to preserve 100% of every Recipe's professional quality dimensions. The separate empirical benchmark remains mandatory before market release; structural tests do not claim model photographic accuracy.
