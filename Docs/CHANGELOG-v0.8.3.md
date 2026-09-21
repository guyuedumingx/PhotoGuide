# PhotoGuide v0.8.3 — UI-complete / model-last cut

This release freezes the product surface before the real DJev/JEV backend is connected.

## Product flow completed

- The complete path is now usable: onboarding → Home → Recipe library → Recipe detail → camera → guidance → capture → review → professional critique report → continue/done.
- Simulator demo mode can capture a generated demo photo, clearly labeled as a demo and never presented as a Photo Library save. This makes capture/review/report UI testable without a physical camera.
- Capture Review now exposes a full professional critique report instead of ending at a generic composition chip.
- The report surface is Recipe-driven and renders every critic dimension, score, confidence, rationale, target status, primary advice, overall score, model source, loading state, and service-not-connected state.
- When no model is connected the report remains complete and explicitly shows empty score slots. Connecting a model only fills the existing schema; it does not change navigation or layout.

## Development-only Preview Critic

Debug builds may enable `Critique UI preview` in Settings or launch with `-usePreviewCritic`. It returns deterministic mock scores and advice solely to exercise the UI. It does not inspect images, make network requests, or represent production photographic judgment. Release builds cannot enable it.

## Architecture boundary

The primary product boundary remains `sampled frames → MultimodalCritic → SemanticCritique → SemanticCriticSession → UI`. The new report reads the same Recipe critic profile and critique response. No scene-specific model contract or new core abstraction was added.

## Validation

- GuidanceCore: 138 tests passed.
- RecipeKit: 21 tests passed.
- Localization: 430 keys × 3 locales.
- Release audit: PASS.
- Swift parser: PASS, including the complete GuidanceUI and UI-test sources.
- Deterministic Xcode project generator includes `CriticReportView.swift` in the GuidanceUI target.

Still intentionally outstanding: real DJev/JEV endpoint integration and empirical model benchmark, plus macOS/Xcode Archive and physical-device QA.
