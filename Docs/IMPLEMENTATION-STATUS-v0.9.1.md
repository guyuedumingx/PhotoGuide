# PhotoGuide v0.9.1 implementation status

## Complete before DJev integration

- Portable reference-image storage in Recipe JSON.
- Ordered Recipe Question schema with Choice / Score / Boolean only.
- No question priority or mismatch-severity ranking.
- Strict bounded-answer validation.
- Runtime states: pending / issue / matched / skipped.
- Author-order initial evaluation and periodic recheck.
- Current issues preserved in author order.
- Horizontal swipe switching between current camera issues.
- Skip selected issue; skip/restore any question; restore all.
- Skipped questions excluded from model requests.
- Camera/optical changes invalidate stale judgments while preserving skips.
- Recipe editor move-up / move-down order controls.
- Reference-image Recipe creation shell.
- Custom Recipe editor, favorites, JSON import, local persistence.
- Continuous capture with no post-shot review/report.
- Debug Preview Judge for deterministic UI/runtime verification only.

## Intentionally blocked on DJev

- Real DJev transport/serialization adapter for `VisualJudgeRequest`.
- Real DJev response decoder into `JudgeAnswer`.
- Automatic inference of author-specific questions from reference images.
- Held-out real-image accuracy and cadence benchmark.

## macOS/Xcode-only validation still required

- iOS SDK type-check/link.
- Simulator UI tests.
- Archive/code signing.
- Camera/photo-library permissions on device.
- Real-device frame cadence, thermal and network behavior.
