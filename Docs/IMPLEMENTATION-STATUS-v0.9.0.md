# PhotoGuide v0.9.0 implementation status

## Complete before DJev integration

- Reference image storage inside portable Recipe JSON.
- Recipe Question schema with Choice / Score / Boolean only.
- Strict validation of allowed answers and score ranges.
- Recipe base priority and mismatch severity.
- Runtime states: pending / issue / matched / skipped.
- Skip current question.
- Skip or restore any question from the camera control sheet.
- Restore all skipped questions.
- Skipped questions excluded from model requests and issue ranking.
- Matched questions periodically rechecked; issues rechecked more frequently.
- Highest effective-priority issue owns the single live problem slot.
- Camera/optical changes invalidate stale judgments while preserving user skips.
- Reference-image Recipe creation shell.
- Custom Recipe editor.
- Favorites.
- JSON import.
- Local persistence.
- Continuous capture with no post-shot review/report.
- Debug Preview Judge for deterministic UI/runtime verification only.

## Intentionally not implemented

- Real DJev transport/serialization adapter for `VisualJudgeRequest`.
- Real DJev response decoder into `JudgeAnswer`.
- Automatic inference of author-specific questions from a reference image.
- Held-out real-image accuracy benchmark.
- Author hint/action extension (explicitly outside v0.9 core).

## macOS/Xcode-only validation still required

- iOS SDK type-check/link.
- Simulator UI tests.
- Archive/code signing.
- Camera/photo-library permissions on device.
- Real-device frame cadence, thermal and network behavior.
