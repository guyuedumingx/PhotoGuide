# PhotoGuide v0.9.3 — Camera interaction polish

## Camera
- Kept camera as the launch/root surface.
- Consolidated the two top-right controls into one compact glass utility capsule while preserving direct layout switching and camera controls.
- Persisted the composition-grid preference.
- Improved tactile feedback for layout switching, lens selection, shutter, camera switching, skip/restore, and question swiping.
- Made the 7:3 guidance panel respect the lower safe area.
- Made issue pagination resilient when a Recipe exposes more than seven simultaneous issues.
- Added an in-camera question management menu; skip/restore no longer needs a separate management page.

## Recipe surfaces
- Added visible favorite/unfavorite control directly on Recipe cards without introducing a Favorites page.
- Restricted the shipping camera flow to question-core Recipes containing both references and questions.
- Legacy bundled Recipes remain parseable compatibility assets but can no longer become the active camera Recipe through the root UI.

## Core invariants retained
- DJev answer space remains Choice / Score / Boolean only.
- No action/advice generation was added.
- No question priority or severity ranking was reintroduced.
- Current issues remain in Recipe author order.
- Continuous capture still has no review/report interruption.
