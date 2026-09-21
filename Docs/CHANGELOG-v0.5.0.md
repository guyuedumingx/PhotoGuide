# PhotoGuide v0.5.0 — Device feedback correction pass

This release starts from upstream `main` commit `db0e36cf5ec6a05ecedb0dd4dab6590ef2bc68b9` and targets issues observed on a physical iPhone.

## Guidance loop fixes

- Reworked portrait visibility semantics so a normal portrait crop is not treated as a HARD full-body failure. A clear face with one cropped edge remains usable for guidance.
- `body_orientation` is now SOFT in shipping portrait recipes. Missing pose evidence no longer traps the controller in repeated HOLD/evidence requests.
- Face yaw is used as a local pose fallback when Vision body pose is unavailable.
- Evidence fallback copy is explicit: missing person, missing face, missing scene anchor, local-only vision, and AI-enhanced states no longer collapse into the same “hold still” message.

## Perception + performance

- Added `VNDetectFaceRectanglesRequest` and a dedicated face overlay.
- Human detection remains the high-cadence guard; face, pose, and saliency run at lower independent cadences and are cached between updates.
- Reduced local perception cadence and throttled insignificant CGRect publications to lower SwiftUI churn on device.
- Automatic saliency anchor selection is enabled for scene-aware recipes; manual tap selection remains available as an override.

## Camera UI

- Safe-area-aware scrims replace the oversized top/bottom masks.
- Coach surfaces are substantially smaller and lighter so they obscure less of the subject.
- Full thirds grid is functional; the currently relevant third is accented.
- Face/person/AI status pills show what the system currently sees and whether remote semantic enhancement is active.
- Removed the unexplained heart button from the empty lower-left camera slot.
- Added a lightweight scan line only while searching for a person; Reduce Motion disables it.

## Product surface

- Added a 3-step first-launch onboarding flow with technology-focused motion.
- Added usable `solo_portrait` and `travel_portrait` recipes alongside environmental portrait.
- Home hero now includes a live intelligence visual instead of a purely static text layout.
- Camera control sheet exposes AI connection state explicitly.

## Configuration

- `DJEV_ENDPOINT` can be supplied as an Xcode build setting and is emitted into generated Info.plist as `DJEVEndpoint`.
- Debug scheme environment variables `DJEV_ENDPOINT` and `DJEV_TOKEN` continue to work.
- Production builds should not embed long-lived bearer tokens in the app.

## Validation

- GuidanceCore: 128 tests pass on Linux Swift.
- RecipeKit: 8 tests pass, including all three shipping recipe presets.
- Localization: 241 keys × English / Simplified Chinese / Traditional Chinese.
- All Swift source files parse successfully in the current environment.

macOS/Xcode is still required for iOS SDK type-checking, UI tests, and physical-device performance validation.

## UI-test determinism

- `-skipOnboarding` bypasses onboarding for navigation/UI regression tests.
- `-resetOnboardingForUITest` forces onboarding even when the simulator/device already has the completion flag, so first-launch tests are deterministic.
