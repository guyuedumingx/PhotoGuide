# PhotoGuide v0.4.4 — Internationalization + Premium Motion

v0.4.4 focuses on two product-quality areas that must be correct before device acceptance: localization and motion. It does not change the frozen GuidanceCore host contract.

## Internationalization

- GuidanceUI now resolves user-facing copy through its own framework bundle instead of embedding Chinese UI strings directly in views.
- Shipping localizations:
  - English (`en`)
  - Simplified Chinese (`zh-Hans`)
  - Traditional Chinese (`zh-Hant`)
- 210 GuidanceUI keys are covered in every shipped locale.
- Camera and Photo Library permission prompts are localized through app-level `InfoPlist.strings` for all three locales.
- The app development region is English; unsupported locales fall back to English.
- The app follows the iOS system / per-app language automatically. No private in-app language state is maintained.
- Zoom, exposure compensation and shutter-duration readouts use `Locale.current` for numeric formatting while retaining photographic units such as `EV`, `ISO`, `s`, and `×`.
- English and Traditional Chinese expansion were accounted for in the coach card, recipe surfaces and camera control sheet instead of relying on fixed Chinese-width layouts.
- Stable accessibility identifiers are used for navigation-critical UI, so UI automation no longer depends on visible Chinese strings.
- `scripts/validate-localization.py` detects missing/orphan/duplicate keys, malformed `.strings`, untranslated CJK in English values, unwrapped CJK literals in GuidanceUI Swift sources, and missing localized privacy descriptions.

## Motion language

A shared `PGMotion` vocabulary now defines micro interaction, state change, settling, navigation/reveal and READY breathing motion. Values are deliberately low-amplitude and short so the camera UI stays calm.

- Home, recipe library and recipe detail use restrained staggered reveal rather than large card movement.
- Recipe category and camera lens selections use `matchedGeometryEffect` for continuous selection movement.
- Camera coach state changes use subtle opacity / scale transitions, including instruction replacement, safety hint, transient notice, review presentation and passive/actionable coach states.
- READY uses a small shutter-ring breathing animation rather than a large pulse.
- Press feedback is centralized in `PGPressButtonStyle` with a very small scale change.
- Captured-photo review uses a single gentle settle instead of continuous cinematic movement.
- Camera overlay Core Animation disables implicit interpolation on high-frequency tracking updates to avoid lag. Anchor, direction cue and focus reticle animate only when their semantic state changes.
- Focus reticle uses a short arrival followed by a delayed fade; the direction cue does not bounce repeatedly.

## Accessibility / Reduce Motion

All SwiftUI motion added in this release respects `accessibilityReduceMotion`. When Reduce Motion is enabled, reveal offsets, button scale feedback, selection state animation, shutter breathing and other nonessential movement are removed or reduced to static state changes.

## Test contract

- GuidanceCore: 128 tests
- RecipeKit: 6 tests
- Localization validator: 210 keys × 3 locales
- UI regression tests now launch explicitly in Simplified Chinese and English and navigate through stable accessibility identifiers.

The Linux build environment can parse all Swift source and execute pure-Swift package tests, but it cannot perform the final iOS SDK type-check/link, simulator UI test run, or real-device motion/camera validation. Those remain Xcode/device acceptance items.
