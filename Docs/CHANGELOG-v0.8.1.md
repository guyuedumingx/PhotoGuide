# PhotoGuide v0.8.1 — Minimal semantic kernel hardening

This release tightens the semantic-first pivot instead of adding more local CV logic.

- Added `SemanticCriticSession`, a tiny stateful model-facing kernel that owns only critique validation, freshness, advice stability and READY reduction.
- Camera UI now consumes the semantic kernel instead of duplicating critic validation/hysteresis in `GuidanceViewModel`.
- Added explicit Recipe quality gates: `requiredForReady` and `minimumConfidence` on critic dimensions. Every shipping Recipe declares at least two model-scored READY gates.
- A model-returned `captureReady=true` can no longer bypass missing/low-confidence required dimensions. A model `captureReady=false` remains a conservative veto.
- Critique acceptance now checks both count coverage and weighted quality-dimension coverage.
- Duplicate critic dimension IDs are reported instead of reaching `Dictionary(uniqueKeysWithValues:)` traps.
- Whole-image multimodal critique is no longer invalidated by optional local subject rebinding. Binding-version checks remain only for legacy Goal observations.
- Semantic frame sampling is scheduled directly from the camera stream before local Vision evaluation, so local detector throttling/failure cannot starve DJev/JEV-style critique.
- While a configured critic is healthy but waiting for a fresh result, local heuristics may draw overlays but do not take over as the photography authority.
- Replaced the no-advice repeating “保持一下” state with a non-blocking “继续取景” semantic observation state.
- Added critic contract version `1` to HTTP requests for future model/backend compatibility.
- Connected remote critic calls to the existing evaluator circuit breaker; rejected/malformed output can now quarantine a bad service instead of looping forever.
- Fixed the deterministic Xcode fallback generator so `RecipeAblation.swift` is included in the RecipeKit target.
- App version bumped to `0.8.1 (19)`.

Validation in this environment:

- GuidanceCore: 138 tests, 0 failures.
- RecipeKit: 20 tests, 0 failures.
- Localization: 382 keys × 3 locales.
- Semantic-first structural ablation: 11/11 Recipes PASS, critic-only quality coverage 100%.
- Critic benchmark harness self-test: PASS.
- Release audit: PASS (empirical held-out critic benchmark still required for market release).
