# PhotoGuide v0.8.0 — Semantic-first pivot

- Promoted the multimodal photography critic from optional enhancement to the primary product intelligence path.
- Added the small model-agnostic `CriticProfile / CriticDimensionSpec / SemanticCritique / CriticAdvice` contract.
- Added Recipe-specific multi-dimensional photographic rubrics to every shipping Recipe.
- Added sampled-frame requests (normally 3 frames) instead of treating remote semantics as a one-image afterthought.
- Added generic `HTTPMultimodalCriticEvaluator`; `HTTPDJevEvaluator` remains a compatibility alias.
- Added model-returned professional advice, overall score, capture readiness, confidence, evidence frame IDs and movement-safety metadata.
- Camera guidance now prefers a fresh semantic critique over subject-specific local heuristics.
- Local Vision is explicitly a low-latency assist and degraded fallback, not the source of domain coverage.
- Replaced the former local-only ablation release invariant with semantic-first ablation: critic-only must preserve 100% of Recipe quality dimensions; local-only is intentionally degraded.
- Added generic `MULTIMODAL_CRITIC_ENDPOINT` / `MULTIMODAL_CRITIC_TOKEN` configuration with DJev compatibility fallbacks.
- Updated onboarding, settings and camera intelligence status to communicate the actual product architecture.
- Added explicit onboarding consent for remote low-resolution sampled-frame critique.
