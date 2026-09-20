# PhotoGuide v0.4.3

## Camera surface

- Split the guidance surface into an actionable full card and a compact passive card. READY, evidence-waiting and user-paused states no longer consume the same vertical space as an active instruction.
- Rebuilt the top bar with geometric centering so the Recipe control stays visually centered independent of trailing camera controls.
- Reduced overlay density, shadows, line weights and guide opacity.
- Added a compact live zoom badge shown only during direct-manipulation zoom.
- Added a restrained shutter flash and save-state shutter animation, with Reduce Motion respected.

## Direct camera manipulation

- `CameraPreviewView` now supports native pinch-to-zoom and emits a typed `CameraZoomGesture` rather than leaking UIKit gesture state into the host layer.
- Interactive zoom is clamped to the active camera's supported display-factor range and is throttled to roughly 30 updates/s.
- Discrete lens selection and pinch zoom can satisfy a camera zoom Action directly; the controller then enters normal post-action verification without requiring a redundant Done tap.
- Optical zoom changes no longer increment `sceneRevision`. They cancel stale semantic work and suppress new remote semantic evaluation for a short transition window instead.

## CameraRuntime correctness

- `CameraService.setZoomFactor` now supports animated and immediate modes. Interactive pinch uses immediate updates; normal button actions keep smooth ramping.
- `CameraFrame.zoomFactor` now reflects the device's actual `videoZoomFactor × displayVideoZoomFactorMultiplier`, including during an active zoom ramp.
- Still capture explicitly uses `AVCapturePhotoOutput.QualityPrioritization.quality`.
- Preview overlay tint now matches the product accent instead of `systemMint`; person/anchor/cue line weights were reduced and the selected background anchor is drawn as a ring.

## Validation

- GuidanceCore: 128 tests passing.
- RecipeKit: 6 tests passing.
- All Swift sources pass `swiftc -parse` in the current Linux environment.
- AVFoundation / SwiftUI type-checking, Xcode linking and physical camera behavior still require macOS + Xcode / iPhone validation.
