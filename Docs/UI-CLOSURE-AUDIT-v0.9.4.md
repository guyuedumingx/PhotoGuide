# PhotoGuide v0.9.4 — UI & interaction closure audit

This audit checks whether visible controls have a complete product path, not merely whether a button exists.

| Surface | Control | Closed behavior |
|---|---|---|
| Camera | Left menu | Opens only Recipe Square / My Recipes / Create Recipe |
| Camera | Current Recipe chip | Opens the in-camera Recipe quick tray |
| Camera | Lower-left Recipe | Opens the same quick tray, matching a camera-first high-frequency selection pattern |
| Camera | Recipe quick tray | Shows reference thumbnails; active first, then favorites, then recent; tap applies immediately |
| Camera | Recipe tray Manage | Returns to the three Recipe management surfaces |
| Camera | Layout | Toggles Overlay / 7:3 and persists |
| Camera | Flash | Explicit Off / Auto / On selection |
| Camera | Grid | Toggle persists |
| Camera | Lens / pinch | Changes zoom and invalidates stale visual judgments |
| Camera | Shutter | Captures continuously; saving does not open a report/review or hold the next shot |
| Camera | Flip | Switches front/back and invalidates stale answers while preserving user skips |
| Camera | Issue carousel | Horizontal switch in author order |
| Camera | Skip | Removes that question from DJev scheduling until restored |
| Camera | Restore / manager | Restores one/all skipped questions without leaving camera |
| Camera | Permission recovery | Opens system Settings |
| Recipe list | Select | Applies Recipe and returns to camera |
| Recipe list | Favorite | Persists favorite state; favorites surface first in quick selection / My Recipes |
| My Recipes | Edit | Opens the same Recipe editor; save updates the existing asset |
| My Recipes | Delete | Requires destructive confirmation and removes favorite state too |
| Create Recipe | Reference image | Creates a valid editable reference/question draft |
| Create Recipe | Blank | Opens editor |
| Create Recipe | JSON import | Validates, saves, activates, returns to camera |
| Editor | References | Add and remove |
| Editor | Questions | Add, remove, reorder; boundary arrows disable rather than no-op |
| Editor | Choice options | Add and remove; minimum two retained |
| Editor | Save | Disabled until references/questions validate; persists on success |
| Editor | Cancel | Dismisses without saving |

## State synchronization checks

- Active Recipe ID persists in `AppStorage`.
- Editing an active Recipe changes the camera view identity using its `updatedAt`, forcing a fresh runtime rather than keeping stale `StateObject` state.
- Switching Recipe recreates the camera model for that Recipe.
- Skipped question state is preserved across optical invalidation where intended.
- Deleting the active Recipe causes the root to fall back to the neutral camera shell.

## Automated structural gate

Run:

```bash
python3 scripts/run-ui-closure-audit.py
```

This is a structural/code-path audit. Actual tap targets, visual overlap, safe-area behavior and camera hardware behavior still require Simulator/device execution on macOS/Xcode.
