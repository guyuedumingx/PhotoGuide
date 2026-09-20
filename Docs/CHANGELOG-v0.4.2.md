# PhotoGuide v0.4.2

## Camera interaction refinement

This release keeps the frozen GuidanceCore host contract and improves the production iPhone surface around it.

### Camera coach

- The main coach card is now the only lower guidance surface. Background-anchor selection no longer produces a second competing prompt card.
- `ActionPresenter` emits structured presentation metadata: preview cue, composition guide and safety sensitivity. Camera UI no longer parses localized instruction strings to infer control behavior.
- Contextual thirds lines are driven by the action presentation contract.
- A subtle directional cue is drawn beside the tracked person for left/right/up/down actions without pretending to have semantic segmentation.
- Safety guidance only appears for actions declared safety-sensitive.
- Transient camera notices now surface focus, anchor, error and adjustment events without occupying persistent UI space.

### Tap semantics and focus

- Before an environment anchor exists, tapping the preview selects the intended background subject and focuses there.
- After an anchor exists, tapping the preview only refocuses. It can no longer silently replace the anchor.
- Reselecting the environment anchor is an explicit control-sheet action.
- `CameraPreviewView` now renders a native focus reticle that fades after interaction.

### Camera control sheet

The old confirmation dialog was replaced with a product-level control sheet containing:

- user-satisfied / resume guidance,
- lock satisfied composition,
- skip current non-HARD goal,
- contextual thirds guide toggle,
- explicit background-anchor reselection,
- session reset,
- exposure compensation and live technical readout when supported.

### Exposure support

`CameraRuntime` now exposes:

- `CameraExposureTelemetry` with ISO, shutter duration and EV bias,
- camera exposure-bias capability range,
- `setExposureBias(_:)`,
- live exposure-bias state.

The UI intentionally exposes EV compensation rather than faking direct ISO/shutter control. AVFoundation auto exposure continues to choose ISO and shutter; the readout is observational and the EV slider is a real device adjustment.

### Interaction polish

- Lens selection, focus, capture, anchor selection and READY transitions use restrained haptic feedback.
- The guidance glass card is slightly lighter and shorter.
- The lens pill is visually quieter.
- The control surface remains photo-first and does not expose controller scores.

## Validation

- GuidanceCore: 128 tests passed.
- RecipeKit: 6 tests passed.
- All Swift sources pass `swiftc -parse` in the Linux workspace.
- iOS frameworks still require Xcode/macOS for SDK type-checking, linker validation and device rendering.
