# PhotoGuide v0.8 — Pre-device and market-release checklist

## Product invariant

The primary product path is:

```text
sampled camera frames
→ Recipe critic profile
→ replaceable multimodal critic
→ multi-dimensional photography assessments
→ one professional next-step suggestion
→ resample
```

Local Vision is support/fallback. Device QA must therefore test the critic path first, not merely prove that local person/saliency detection runs.

## A. Repository / Linux RC gate

- [x] GuidanceCore semantic critic protocol compiles/tests.
- [x] RecipeKit has explicit domain critic profiles.
- [x] Every shipping Recipe has at least five professional quality dimensions.
- [x] `critic-only` structural ablation preserves 100% Recipe quality-dimension coverage.
- [x] `local-only` is labeled degraded, not full product capability.
- [x] generic HTTP multimodal critic adapter exists; DJev is not hard-coded as the architecture.
- [x] sampled-frame request buffer exists.
- [x] remote AI is opt-in and Release requires HTTPS.
- [x] tokens are not embedded in project configuration.
- [x] English / Simplified Chinese / Traditional Chinese localization contract.
- [x] deterministic Xcode project generation.
- [x] privacy manifest and app icon assets.

Run:

```bash
swift test --package-path Packages/GuidanceCore
swift test --package-path Packages/RecipeKit
python scripts/validate-localization.py
python scripts/run-ablation.py
python scripts/evaluate-critic-benchmark.py --self-test
./scripts/prepare-xcode.sh
python scripts/release-audit.py
```

## B. macOS / Xcode gate

```bash
./scripts/prepare-xcode.sh
xcodebuild \
  -project PhotoGuide.xcodeproj \
  -scheme PhotoGuideApp \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Then run the UI test target and an Archive with the real signing team. Fix Apple-framework type, actor-isolation, permission, resource or linker failures before changing product behavior.

## C. Real-device semantic loop

Validate with the production-like critic endpoint enabled and consent granted:

1. camera preview remains responsive while critic requests are in flight;
2. one request at a time; no frame-by-frame upload;
3. sampled-frame IDs/timestamps are in order;
4. stale previous-scene responses never overwrite current advice;
5. each Recipe sends its own critic dimensions/rubrics;
6. model advice appears without requiring a local person detector;
7. food/flower/product/pet/landscape/architecture all reach useful semantic guidance;
8. professional advice does not flicker every result; hysteresis is perceptually stable;
9. `captureReady` does not oscillate from adjacent sampled windows;
10. model timeout/5xx degrades to Basic mode without freezing camera/capture;
11. reconnect restores AI critique without reviving stale advice;
12. remote-AI off means no frame upload and UI does not claim AI professional review.

## D. Cross-domain device matrix

Do not validate only portraits. Use independent sessions for at least:

- portrait / close-up portrait;
- food;
- flower / plant;
- product / still life;
- pet / moving subject;
- landscape;
- architecture.

Cross with clean/cluttered backgrounds, normal/low/backlight, portrait/landscape orientation and multiple lenses where meaningful.

Record:

- time to first useful critique;
- P50 / P95 critic latency;
- advice churn/repetition;
- capture-ready stability;
- user-followed advice success;
- request failures/timeouts;
- preview FPS, CPU, memory, thermal state and battery impact.

## E. Empirical photography-quality gate

Architecture tests cannot prove advice quality. Before market release, freeze a held-out dataset and human photography labels according to `Docs/CRITIC-BENCHMARK-PROTOCOL-v0.8.md`.

Required ablations use the same frozen samples:

- `full` sampled-frame + Recipe-specific rubric;
- `single_frame`;
- `generic_rubric`;
- one or more alternative model candidates;
- optional `local_only` degraded baseline.

Run:

```bash
python scripts/evaluate-critic-benchmark.py Benchmarks/critic-benchmark.jsonl \
  --json-out Docs/CRITIC-BENCHMARK-RESULTS.json \
  --markdown-out Docs/CRITIC-BENCHMARK-RESULTS.md
python scripts/release-audit.py --market-release
```

Do not use the synthetic fixture in `Tests/Fixtures` as product evidence.

## F. Privacy / failure paths

- [ ] remote critique consent is explicit and reversible;
- [ ] privacy policy matches the deployed service's actual retention and subprocessors;
- [ ] no long-lived service secret exists in the shipped binary;
- [ ] camera/photo permissions denied and later restored behave correctly;
- [ ] background/foreground invalidates stale semantic context;
- [ ] network loss and high latency never block the shutter;
- [ ] thermal serious/critical lowers remote/local workload without corrupting state;
- [ ] repeated malformed critic responses are circuit-broken;
- [ ] unsafe physical-movement advice still receives the movement warning boundary.

## G. Release meaning

Passing the normal repository audit means **release-candidate structure is internally consistent**.

Market-ready means all of the following are also true:

1. production critic endpoint deployed;
2. held-out empirical critic benchmark passed against pre-declared thresholds;
3. Xcode build/archive passed;
4. physical-device matrix passed;
5. privacy/store/signing requirements completed.

Never substitute local Vision success for multimodal critic quality, and never substitute structural ablation for empirical photography-quality validation.
