# PhotoGuide v0.9.4 — Camera loop closure

## Camera-first interaction
- Added a direct Recipe quick selector on the camera surface. The current Recipe chip and the lower-left Recipe control both open the same bottom tray.
- The tray uses reference-image thumbnails, keeps the active Recipe first, then favorites, then recently updated Recipes.
- Selecting a Recipe returns immediately to live capture; no Recipe detail page is introduced.
- Kept the left-top menu for full Recipe management only.
- Changed flash from repeated cycle behavior to explicit Off / Auto / On choices.
- Kept grid, guidance layout, lens, shutter, camera switch, question swipe, skip and restore on the camera surface.
- The bottom capture row now follows the familiar camera pattern of secondary capability on the left, primary shutter in the center, camera flip on the right.

## Recipe management closure
- My Recipes now supports edit and delete without adding another top-level page.
- Favorite Recipes are surfaced first in My Recipes and in the in-camera quick selector.
- Editing the currently active Recipe now rebuilds the camera runtime using the asset `updatedAt`, preventing stale questions/reference images.
- Recipe cards now use the first reference image as their visual identity when available.

## Recipe editor closure
- Choice options can now be removed as well as added.
- Question move-up/move-down controls disable at list boundaries instead of silently doing nothing.
- The final remaining question cannot be deleted accidentally.

## Validation
- Added `scripts/run-ui-closure-audit.py` to verify the visible control paths stay connected.
- Added a UI regression test contract for the camera Recipe quick selector.
- Real DJev frame/reference accuracy remains intentionally unclaimed until the real model is connected.
