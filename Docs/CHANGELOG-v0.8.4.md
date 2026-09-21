# PhotoGuide v0.8.4 — Recipe-first continuous capture

## Product contract

PhotoGuide now has only two first-class product concepts:

1. **Live shooting guidance** — the camera stays open and the system continuously selects one useful next shooting suggestion from the active Recipe.
2. **Recipe** — a portable description of photographic intent and critic dimensions/rubrics. Recipe is data, not a new hard-coded controller per scene.

There is no post-capture review, critique report, confirmation step, or success screen. A successful capture releases the shutter as soon as camera capture completes; photo-library persistence continues off the capture-critical path. Save failures may surface as a non-blocking status, but successful shots never interrupt shooting.

## Recipe workspace

- **Reference image → Recipe draft:** PhotosPicker, loading/error states, draft editor, persistence, and camera consumption are complete. The current `ReferenceImageRecipeGenerator` intentionally creates a neutral critic-only draft and does **not** claim image-content understanding. Real DJev/JEV replaces only this adapter.
- **Favorite:** official and user Recipes can be favorited and filtered.
- **Import:** JSON `RecipeDTO` or stored Recipe asset can be imported, validated, normalized, and persisted.
- **Custom/edit:** title, intent, domain, tags, critic dimensions, rubric, and weights are editable. User Recipes are constructed critic-only with zero Goal/Action/node requirements.
- **Use in camera:** custom/imported/generated Recipe can launch the same camera workflow as built-in Recipes through `GuidanceCameraView(recipe:)`.

## Core boundary

Primary path: `Recipe → sampled frames → MultimodalCritic → one live suggestion → camera UI`.

Not first-class dependencies: local subject detection, Goal graphs, Action graphs, post-capture reports, per-scene controller classes. They may exist as optional adapters/fallbacks but cannot be prerequisites for model guidance or Recipe validity.

## Structural ablation

Run:

```bash
python3 scripts/run-product-ablation.py
```

The v0.8.4 ablation checks that:

- report/review UI is absent from the shipping source and Xcode graph;
- capture returns control before photo-library persistence;
- reference-image, favorite, import, custom/edit Recipe flows exist;
- every built-in Recipe retains its critic dimensions when legacy Goal/Action/local-perception structures are removed;
- critic-only Recipe construction compiles with no nodes/goals/actions.

See `Docs/ABLATION-REPORT-v0.8.4.md` for generated results. This is a **structural** ablation only. Photography-quality ablation (Recipe vs no Recipe, frame-count variants, model variants) requires the real DJev/JEV endpoint and a held-out image/video benchmark; v0.8.4 makes no empirical quality claim without that evidence.

## Intentionally remaining

- Real DJev/JEV reference-image understanding and live multimodal inference.
- Empirical photography-quality benchmark against the real model.
- Final Xcode iOS SDK build/archive and physical-device QA on macOS.
