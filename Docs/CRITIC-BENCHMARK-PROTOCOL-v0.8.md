# PhotoGuide v0.8 — Empirical Multimodal Critic Benchmark Protocol

## Purpose

Structural tests can prove that a Recipe has dimensions, rubrics and a model-independent contract. They cannot prove that a multimodal model gives good photography advice.

A market release therefore needs a second, empirical layer that measures the actual critic against human photography judgments. This benchmark is model-facing: it remains valid when DJev is replaced by another low-latency multimodal/System-1/JEV-style evaluator.

## Unit of evaluation

One benchmark row represents one captured camera state for one Recipe and one evaluator variant. The source image/frame group must be frozen before variants are compared.

Recommended fields are accepted by `scripts/evaluate-critic-benchmark.py`:

```json
{
  "sample_id": "food-clutter-0042",
  "recipe_id": "official.food",
  "variant": "full",
  "human": {
    "capture_ready": false,
    "scores": {
      "composition": 0.58,
      "food_presentation": 0.82,
      "lighting": 0.63
    }
  },
  "model": {
    "capture_ready": false,
    "scores": {
      "composition": 0.61,
      "food_presentation": 0.76,
      "lighting": 0.67
    }
  },
  "advice_usefulness": 0.9,
  "advice_safe": true,
  "latency_ms": 286
}
```

Human dimension scores should use the same Recipe rubric as the model. `advice_usefulness` is normalized to `0...1` from a blinded reviewer rating.

## Required domains

A release benchmark must not be portrait-heavy. At minimum it should contain independent scenes from:

- portrait / close-up portrait;
- food;
- flower / plant;
- product / still life;
- pet / moving subject;
- landscape;
- architecture.

For each domain, deliberately include easy and hard examples across:

- clean and cluttered backgrounds;
- normal light, low light and strong backlight;
- near, medium and far framing where meaningful;
- stable and moving scenes where meaningful;
- vertical and horizontal compositions;
- at least two device/lens configurations where meaningful.

Do not reuse adjacent frames from the same short clip as independent test samples. Split by scene/session, not by frame.

## Human reference

For serious release evaluation, use at least three independent reviewers with photography competence. Reviewers see the Recipe intent and rubric but not the model output. Aggregate dimension scores with the median. Resolve only large disagreements; do not tune the model to individual reviewers.

The benchmark set used for the final gate must be held out from prompt/rubric tuning.

## Required ablations

The same frozen sample set should be evaluated with at least:

1. `full` — Recipe-specific rubric + sampled-frame critic.
2. `single_frame` — same model/rubric but only newest frame.
3. `generic_rubric` — remove Recipe-specific photographic expertise.
4. `model_candidate_*` — alternative multimodal evaluator(s) behind the same contract.
5. `local_only` — optional degraded baseline; it is not expected to match the professional critic.

This directly tests the product hypothesis: temporal sampled-frame, domain-specific multimodal critique should add value beyond generic or local-only logic.

## Metrics

The benchmark tool reports:

- capture-ready accuracy / precision / recall;
- dimension score MAE against the human reference;
- dimension score coverage;
- advice usefulness;
- advice safety rate;
- P50 / P95 service latency;
- delta of each ablation versus `full`.

Additional product telemetry should measure advice churn, repeated advice, time-to-useful-advice and successful user correction after following advice.

## Release interpretation

No single numeric threshold is universal across every future model. A release candidate must establish and version explicit thresholds after the first sufficiently large human-labeled run. The important invariant is that thresholds are set **before** final evaluation and are applied to held-out data.

Suggested initial investigation targets, not pre-claimed release results:

- dimension score coverage >= 95%;
- advice safety >= 99%;
- P95 latency low enough that guidance remains interactive;
- `full` should not regress materially against `single_frame` or `generic_rubric` on human-alignment metrics;
- every shipping Recipe must have enough samples to expose domain-specific failure, rather than passing only on aggregate.

## Running the evaluator

```bash
python scripts/evaluate-critic-benchmark.py Benchmarks/critic-benchmark.jsonl \
  --json-out Docs/CRITIC-BENCHMARK-RESULTS.json \
  --markdown-out Docs/CRITIC-BENCHMARK-RESULTS.md
```

The repository intentionally does not ship fabricated empirical results. Until a real frozen dataset, a real evaluator endpoint and blinded human labels are supplied, this protocol is a release gate specification, not evidence that model quality has passed.
