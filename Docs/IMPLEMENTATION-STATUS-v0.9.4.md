# PhotoGuide v0.9.4 — Implementation status

## Shipping product surface

The app still has one primary surface: **Camera**. The only secondary destinations remain:

1. Recipe Square
2. My Recipes
3. Create Recipe

No Home, onboarding, report, post-shot review, standalone settings, Recipe detail, or camera-control page has been reintroduced.

## Camera loop

Closed in code:

- launch directly into camera;
- choose Recipe directly from the camera using the top Recipe chip or lower-left Recipe button;
- horizontal reference-thumbnail Recipe tray;
- return immediately to live camera after selection;
- overlay and 7:3 guidance layouts;
- horizontal issue switching in Recipe author order;
- skip current issue;
- restore individual/all skipped questions;
- direct lens choice and pinch zoom;
- explicit flash Off / Auto / On;
- persistent composition grid;
- front/back camera switching;
- continuous shutter, with Photo Library persistence detached from the next capture;
- camera permission recovery through Settings.

## Recipe loop

Closed in code:

- create from reference image draft;
- create blank Recipe;
- import JSON;
- add/remove reference images;
- add/remove/reorder questions;
- add/remove Choice options;
- Score and Boolean editing;
- save/update locally;
- favorite/unfavorite;
- edit existing Recipe;
- delete with confirmation;
- active Recipe refreshes after editing.

## Deliberately unfinished

- Real DJev `current frame + reference images + question -> Choice/Score/Boolean` transport and model accuracy.
- Automatic extraction of an author's real photographic method from reference images (the current generator is only a valid editable draft).
- Remote Recipe marketplace/catalog/backend.
- macOS/Xcode iOS SDK type-check, Simulator UI execution, Archive/signing, physical-device camera/thermal/network QA.

No Preview/Mock result is used as evidence for real DJev image understanding.
