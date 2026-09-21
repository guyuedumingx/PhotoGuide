# PhotoGuide v0.5.0 — Physical-device validation focus

This build is a device-feedback candidate, not a claim that iOS hardware validation is complete.

## Regression targets from the previous device run

1. A normal close portrait with the lower body outside frame must **not** loop on “keep the whole person in frame”.
2. Missing Vision body-pose evidence must **not** trap the controller in repeated HOLD / “hold still”.
3. A visible face should show the face guide and the camera HUD should report face acquisition.
4. The camera preview should remain responsive while human detection runs; face / pose / saliency are intentionally lower cadence.
5. Top and bottom scrims must respect safe areas and should not create large opaque bands.
6. The coach card should leave most of the subject visible.
7. Thirds grid must visibly toggle; the currently actionable third receives an accent line.
8. Empty lower-left camera control has no unexplained heart action. It becomes a thumbnail only after capture.
9. First launch should enter onboarding unless UI tests pass `-skipOnboarding`.
10. Environment portrait, solo portrait, and travel portrait must all start distinct Recipe presets.
11. AI state must be truthful: local-only without `DJEV_ENDPOINT`; AI connected/enhanced only when an endpoint is actually configured and responding.

## Suggested 10-minute smoke test

- Launch fresh install → complete onboarding.
- Start Environment Portrait with a head-and-torso framing.
- Confirm face/person status appears and guidance progresses beyond visibility HOLD.
- Move left/right and verify guide direction changes correctly.
- Toggle thirds grid and verify visible change.
- Open camera controls and confirm AI state is explicit.
- Switch to Solo Portrait and Travel Portrait from the home/library and verify each launches.
- Capture a photo → review → continue shooting.
- Background/foreground the app once and confirm guidance reacquires the current scene instead of reusing stale READY state.

## AI / DJev configuration

`DJEV_ENDPOINT` is a build setting. Debug can also use the `DJEV_ENDPOINT` / `DJEV_TOKEN` scheme environment variables. Do not embed a long-lived bearer token in a production app bundle.

The local Vision + GuidanceCore loop remains usable without DJev. DJev is expected to improve semantic pose / scene relationship / aesthetic judgments, not basic person-presence correctness.
