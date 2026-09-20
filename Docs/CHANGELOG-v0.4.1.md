# PhotoGuide v0.4.1 — Full iPhone product UI implementation

This pass implements the product surface directly in SwiftUI rather than leaving it as a visual specification.

## Product flow

- Rebuilt Home as a premium camera-first entry surface.
- Added a dedicated Recipe Library with category filters.
- Added a complete Recipe Detail page before entering the camera.
- Environment Portrait is the only live recipe; upcoming recipes are visibly non-interactive rather than fake functionality.
- Reworked the capture review into a photo-first result screen with Continue and Done paths.

## Camera coach

- Kept one dominant instruction and one dominant action.
- Moved session controls into the centered recipe pill to reduce top-bar noise.
- Contextual thirds line appears only for left/right composition guidance.
- Vision person detection is shown as subtle corner guides rather than a fake segmentation silhouette.
- Background anchor remains user-selected and explicitly visible.
- Safety hint appears only for movement actions.
- Secondary actions are plain text; the primary action remains the only filled button.
- Lens selector, shutter, recent-photo thumbnail, camera flip, flash and grid controls now share one visual system.
- READY gets a subtle shutter pulse rather than a large status panel.

## Automatic camera actions

- Camera zoom actions can now be executed directly by the primary button.
- `camera.zoom_2x` chooses the available lens/zoom nearest 2×.
- `camera.zoom_out` chooses the nearest valid wider option.
- After the camera applies the zoom, the normal GuidanceCore verification loop is still used; automatic execution does not bypass action verification.
- Human movement / pose actions remain manual and continue to use “完成调整”.

## Capture review

- Preserves the latest captured photo as a thumbnail after closing review.
- Tapping the thumbnail reopens the latest capture.
- Review language remains qualitative (conformance states) rather than fake numerical scoring.

## Validation

- Core and RecipeKit remain unchanged behind the frozen host boundary except for host-side automatic camera execution.
- Linux validation includes pure Swift unit tests plus `swiftc -parse` for every Swift source file.
- AVFoundation / SwiftUI type-checking and device rendering still require macOS + Xcode.
