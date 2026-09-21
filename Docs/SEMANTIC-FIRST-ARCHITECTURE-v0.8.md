# PhotoGuide v0.8 — Semantic-first Architecture

## Product invariant

PhotoGuide is **not** a person detector with photography UI layered on top.
The product core is a replaceable, low-latency multimodal photography critic:

```text
sampled camera frames
        ↓
Recipe critic profile
        ↓
multimodal/System-1/JEV-style evaluator
        ↓
multiple quality scores + confidence + evidence
        ↓
one professional next-step suggestion
        ↓
resample and re-evaluate
```

DJev is the first intended implementation. It is not a permanent architectural dependency. Any future multimodal model can replace it if it implements the same critic contract.

## Minimal core

The semantic product core intentionally contains only five concepts:

1. `CriticProfile` — what this Recipe wants the model to judge.
2. `CriticDimensionSpec` — one photographic quality dimension and its rubric.
3. `SemanticImageSample` — a sampled low-resolution frame.
4. `SemanticCritique` — multi-dimensional scores plus professional advice.
5. `SemanticCritiqueReducer` — stable fallback selection/readiness logic when the model does not explicitly provide it.

Everything else is support infrastructure.

## What local Vision is allowed to do

Local Vision is optional assistance. It may provide:

- low-latency overlays;
- face/person/saliency boxes;
- camera telemetry;
- basic exposure/geometry hints;
- emergency/basic-mode guidance when the critic service is unavailable.

Local Vision must **not** define the product's supported subject categories. A flower, food plate, pet, building, landscape, person, or future category remains valid because the Recipe asks the multimodal critic to judge photographic quality, not because a local detector has a matching class.

## Recipe boundary

A shipping Recipe owns the photographic expertise. Each Recipe declares:

- intent;
- 5+ quality dimensions;
- domain-specific scoring rubrics;
- weight;
- target score;
- actionability;
- preferred sampled-frame count;
- advice style.

Examples:

- portrait: composition, expression/pose, light, separation, color, timing;
- food: composition, plating/appetite, light, background, color, detail;
- product: product clarity, reflections, geometry, background cleanliness;
- pet: expression/timing, focus/motion, light, background;
- landscape: composition, depth/layers, atmosphere, color, clarity;
- architecture: composition, perspective/geometry, lines/rhythm, light, clutter.

The client does not need a new controller branch for each category.

## Evaluation cadence

The camera does not stream every frame to the remote model. The v0.8 client:

- makes at most one critic request at a time;
- targets roughly one request every 0.55 s while active;
- stores a tiny bounded JPEG sample window;
- asks each Recipe for 1–5 samples, normally 3;
- sends a maximum 640 px image dimension at compressed quality;
- rejects results outside the current binding/scene context;
- accepts remote inference latency on a wider frame window than local CV fusion.

This keeps the model fast enough to behave like a photography System-1 evaluator without creating a full video-understanding stack.

## Decision priority

When a fresh valid multimodal critique exists, it is the primary product decision source.

```text
fresh SemanticCritique
    ├─ captureReady → show READY
    ├─ explicit advice → show model's professional advice
    └─ no explicit advice → choose largest weighted score deficit

no fresh critique
    ├─ critic configured/in-flight → show evaluating state
    └─ critic unavailable → Basic mode local fallback
```

The local GoalEngine remains useful for camera actions, safety, verification, replay, and degraded operation. It is no longer the source of PhotoGuide's domain generality.

## Safety boundary

Professional advice is allowed to be free-form explanatory text, but the response also declares an advice kind and whether physical movement is required. The UI can therefore retain movement warnings and avoid silently automating unsafe physical actions.

## Release ablation invariant

`critic-only` must retain 100% of every Recipe's quality dimensions even when all local Vision assistance is removed.

`local-only` is explicitly classified as degraded capability. Passing a local-only readiness check is not evidence that the full PhotoGuide product is functioning.

See `Docs/ABLATION-REPORT-v0.8.0.md`.
