# PhotoGuide semantic kernel v0.8.2 — critic-core cut

## Non-negotiable product invariant

The product is a sampled-frame multimodal photography critic. Local Vision is optional.

```text
camera frames
    ↓
small temporal sampler
    ↓
CriticProfile (Recipe: what to judge)
    ↓
MultimodalCritic (DJev/JEV/future System-1 model)
    ↓
SemanticCritique (scores + confidence + professional advice)
    ↓
SemanticCriticSession (validate + stabilize + READY/advice)
    ↓
UI
```

The primary path must not require GoalEngine, Observation, subject tracking, face detection, saliency, camera telemetry or a known subject class.

## Core contract

`MultimodalCritic` receives only:

- one `CriticProfile`;
- 1–5 sampled JPEG frames;
- output locale.

It returns one `SemanticCritique`.

That is the model boundary. Transport compatibility stays inside the HTTP adapter.

## Recipe rule

A Recipe answers **what professional qualities should be judged**, not **how the client should detect the scene**. A Recipe can add/remove dimensions without a controller branch. New model providers can replace DJev without changing Recipe or UI semantics.

## Local capability rule

Local CV may improve overlays, interaction latency, focus UX, telemetry, automation and degraded fallback. Removing all local CV must not remove any professional quality dimension from the multimodal critic path.

## Ablation acceptance

A release fails if any of the following is true:

1. critic requests require Goal/Observation slots;
2. a subject category must be detected locally before critique can run;
3. READY can be produced from local-only heuristics while a healthy critic is pending;
4. adding a new photographic domain requires a new controller branch rather than a Recipe profile;
5. swapping the model provider requires changing Recipe semantics.
