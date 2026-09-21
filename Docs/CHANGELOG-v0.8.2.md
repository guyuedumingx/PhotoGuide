# PhotoGuide v0.8.2 — critic-core cut

This revision removes the last Goal/Observation dependency from the primary multimodal evaluation path.

- Added the model-agnostic `MultimodalCritic` protocol to GuidanceCore.
- Moved sampled image payloads into the semantic core as `CriticImageSample`.
- `GuidanceViewModel` now calls the critic directly from sampled camera frames.
- Removed EvaluationCoordinator, Goal slots, Observation validation and local binding versions from the critic request path.
- Kept early DJev wire compatibility inside the HTTP adapter only; it no longer leaks into product-core semantics.
- Added a tiny bounded retry/backoff state for critic transport failures.
- Local Vision remains available for overlays, camera interaction and degraded fallback, but cannot gate the professional critic.
