# PhotoGuide v0.9.4 — Camera-first closed loop

PhotoGuide is a camera-first iOS app built around a deliberately small System-1 loop:

```text
Current camera frame
        +
Recipe reference images
        +
One Recipe-authored question
        ↓
      DJev
        ↓
Choice / Score / Boolean
        ↓
Recipe-authored issue text
```

DJev does not plan actions, write coaching copy, rank problems, or decide how the user should move. A Recipe defines what difference should be judged against its reference images. PhotoGuide samples frames, asks bounded questions, keeps answers fresh, and shows the current differences in the author's order.

## Product surface

The app launches directly into **Camera**. There are only three secondary destinations behind the upper-left menu:

1. **Recipe Square**
2. **My Recipes**
3. **Create Recipe**

There is no Home page, onboarding flow, report page, post-shot review, standalone settings page, Recipe detail page, or camera-control sheet.

## Camera

The camera owns the high-frequency workflow.

- Select Recipe without leaving the camera: tap the current Recipe chip or the lower-left Recipe control to open a horizontal reference-thumbnail tray.
- The tray keeps the active Recipe first, then favorites, then recently updated Recipes.
- Two guidance layouts:
  - **Overlay** — issue card floats over the live preview.
  - **7:3 split** — roughly 70% live camera and 30% independent issue area.
- Multiple current issues remain in Recipe author order and can be switched horizontally.
- Skip the current question, restore skipped questions, or manage skip state without leaving the camera.
- Explicit flash Off / Auto / On, persistent grid, lens choice, pinch zoom and front/back camera switching.
- Continuous shutter: once a frame is captured, the next shot can proceed while Photo Library persistence continues independently.

## Recipe contract

A new Recipe needs only:

```text
Recipe
├── references[]
└── questions[]   // array order is author order
```

Each question returns one bounded type:

```text
choice  -> predefined option IDs
score   -> bounded numeric range
boolean -> true / false
```

Issue strings describe the current difference. They are not action instructions. There is no question priority and no required action/advice/hint field.

See `Docs/RECIPE-QUESTION-CONTRACT-v0.9.1.md`.

## Recipe creation and management

- Start from a reference image, blank Recipe, or JSON import.
- Add/remove reference images.
- Add/remove/reorder Choice / Score / Boolean questions.
- Add/remove Choice options.
- Save/update locally.
- Favorite/unfavorite.
- Edit and delete from My Recipes.
- Editing the active Recipe refreshes the camera runtime instead of leaving stale question state.

Reference-image creation currently makes a structurally valid editable draft. Real extraction of an author's photographic method is intentionally reserved for real DJev integration.

## Validation

```bash
make test
python3 scripts/run-question-ablation.py
python3 scripts/run-ui-closure-audit.py
python3 scripts/release-audit.py
```

See `Docs/UI-CLOSURE-AUDIT-v0.9.4.md` for the control-by-control closure inventory.

## Intentionally unfinished

- real DJev current-frame vs reference-image judgments;
- held-out DJev accuracy/consistency benchmark;
- remote Recipe marketplace backend/catalog;
- iOS SDK type-check, Simulator UI execution, Archive, and physical-device QA, which require macOS/Xcode.

The Debug `PreviewVisualJudge` exists only to exercise UI/runtime state and does not claim to inspect image content.
