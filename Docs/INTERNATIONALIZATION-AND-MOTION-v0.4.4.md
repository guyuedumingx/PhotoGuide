# Internationalization & Motion Contract — v0.4.4

This document defines the product contract for adding copy and motion after v0.4.4.

## Localization contract

1. Any user-visible GuidanceUI string must pass through `L(_:)` or a locale-aware formatting helper.
2. Add the key to all shipped `Localizable.strings` files in the same change.
3. Do not read localization from `Bundle.main` inside GuidanceUI. GuidanceUI is a framework and owns its resources; use the framework bundle supplied by `PGL10n`.
4. Do not persist a separate app-language preference. The product follows the iOS system/per-app language.
5. Do not construct translated sentences by concatenating independently translated fragments when word order could differ. Add a complete localization key instead.
6. Numeric values that are visible to the user must use `Locale.current` where locale conventions matter.
7. Accessibility identifiers are stable machine identifiers and must not be localized. Accessibility labels are user-facing and must be localized.
8. Camera/Photo privacy prompts live in app-level localized `InfoPlist.strings`.
9. Run `make localization-test` after any user-facing copy change.

### Shipped locales

| Locale | Resource | Notes |
| --- | --- | --- |
| English | `en.lproj` | development/fallback language |
| Simplified Chinese | `zh-Hans.lproj` | native source-language copy |
| Traditional Chinese | `zh-Hant.lproj` | Traditional terminology, not only glyph conversion |

## Motion contract

The camera preview is the product's visual priority. Motion must communicate state, not decorate the screen.

1. Use `PGMotion` tokens instead of inventing arbitrary animation timings in each view.
2. Prefer opacity, very small translation and very small scale changes. Avoid large spring travel, repeated bouncing, rotation and continuous decorative motion.
3. `matchedGeometryEffect` is appropriate for a selection that conceptually moves between adjacent controls (category/lens selection), not for unrelated surfaces.
4. High-frequency Vision tracking geometry must update without implicit Core Animation; animate semantic transitions (new focus point, new anchor, new direction cue) only.
5. READY may breathe subtly. Guidance arrows do not repeatedly bounce.
6. Press feedback must remain below the threshold where the control appears to jump under the finger.
7. Every nonessential animation must respect `accessibilityReduceMotion`.
8. Avoid introducing motion that delays capture, blocks camera input, or changes controller timing.

## Acceptance checks

Before release on macOS/Xcode:

- Switch the app language between English, Simplified Chinese and Traditional Chinese in iOS per-app language settings and relaunch.
- Inspect the smallest supported iPhone width for clipped coach/action/control text.
- Enable Larger Text and verify critical actions remain reachable.
- Enable Reduce Motion and verify the camera remains visually stable while all state changes remain understandable.
- Exercise lens switching, tap focus, anchor selection, READY, capture and photo review at 60/120 Hz display refresh rates.
- Run Xcode UI tests in both `en` and `zh-Hans` launch configurations.
