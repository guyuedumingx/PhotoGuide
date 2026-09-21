#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    xs = sorted(values)
    if len(xs) == 1:
        return xs[0]
    pos = (len(xs) - 1) * q
    lo = math.floor(pos)
    hi = math.ceil(pos)
    if lo == hi:
        return xs[lo]
    frac = pos - lo
    return xs[lo] * (1 - frac) + xs[hi] * frac


def safe_mean(values: list[float]) -> float | None:
    return statistics.fmean(values) if values else None


def load_rows(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open() as fh:
        for line_number, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            try:
                row = json.loads(line)
            except Exception as exc:
                raise ValueError(f"{path}:{line_number}: invalid JSON: {exc}") from exc
            if not isinstance(row, dict):
                raise ValueError(f"{path}:{line_number}: row must be an object")
            rows.append(row)
    if not rows:
        raise ValueError(f"{path}: benchmark contains no rows")
    return rows


def validate_row(row: dict[str, Any], index: int) -> None:
    prefix = f"row {index}"
    for key in ("sample_id", "recipe_id", "variant", "human", "model"):
        if key not in row:
            raise ValueError(f"{prefix}: missing {key}")
    if not isinstance(row["human"], dict) or not isinstance(row["model"], dict):
        raise ValueError(f"{prefix}: human/model must be objects")
    for side in ("human", "model"):
        scores = row[side].get("scores", {})
        if not isinstance(scores, dict):
            raise ValueError(f"{prefix}: {side}.scores must be an object")
        for dim, value in scores.items():
            if not isinstance(value, (int, float)) or not 0 <= float(value) <= 1:
                raise ValueError(f"{prefix}: {side}.scores.{dim} must be in 0...1")
        ready = row[side].get("capture_ready")
        if ready is not None and not isinstance(ready, bool):
            raise ValueError(f"{prefix}: {side}.capture_ready must be boolean/null")
    latency = row.get("latency_ms")
    if latency is not None and (not isinstance(latency, (int, float)) or latency < 0):
        raise ValueError(f"{prefix}: latency_ms must be >= 0")
    usefulness = row.get("advice_usefulness")
    if usefulness is not None and (not isinstance(usefulness, (int, float)) or not 0 <= usefulness <= 1):
        raise ValueError(f"{prefix}: advice_usefulness must be in 0...1")
    safe = row.get("advice_safe")
    if safe is not None and not isinstance(safe, bool):
        raise ValueError(f"{prefix}: advice_safe must be boolean/null")


def summarize(rows: list[dict[str, Any]]) -> dict[str, Any]:
    by_variant: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for i, row in enumerate(rows, 1):
        validate_row(row, i)
        by_variant[str(row["variant"])].append(row)

    result: dict[str, Any] = {"variants": {}, "sample_count": len(rows)}
    for variant, items in sorted(by_variant.items()):
        ready_pairs: list[tuple[bool, bool]] = []
        abs_errors: list[float] = []
        score_pairs = 0
        expected_scores = 0
        usefulness: list[float] = []
        safety: list[bool] = []
        latency: list[float] = []
        recipes: set[str] = set()

        for row in items:
            recipes.add(str(row["recipe_id"]))
            human = row["human"]
            model = row["model"]
            if human.get("capture_ready") is not None and model.get("capture_ready") is not None:
                ready_pairs.append((bool(human["capture_ready"]), bool(model["capture_ready"])))

            hs = human.get("scores", {})
            ms = model.get("scores", {})
            expected_scores += len(hs)
            for dim, h in hs.items():
                if dim in ms:
                    score_pairs += 1
                    abs_errors.append(abs(float(h) - float(ms[dim])))

            if row.get("advice_usefulness") is not None:
                usefulness.append(float(row["advice_usefulness"]))
            if row.get("advice_safe") is not None:
                safety.append(bool(row["advice_safe"]))
            if row.get("latency_ms") is not None:
                latency.append(float(row["latency_ms"]))

        tp = sum(1 for h, m in ready_pairs if h and m)
        tn = sum(1 for h, m in ready_pairs if not h and not m)
        fp = sum(1 for h, m in ready_pairs if not h and m)
        fn = sum(1 for h, m in ready_pairs if h and not m)
        denom = len(ready_pairs)
        accuracy = (tp + tn) / denom if denom else None
        precision = tp / (tp + fp) if tp + fp else None
        recall = tp / (tp + fn) if tp + fn else None

        result["variants"][variant] = {
            "samples": len(items),
            "recipe_count": len(recipes),
            "ready_accuracy": accuracy,
            "ready_precision": precision,
            "ready_recall": recall,
            "dimension_mae": safe_mean(abs_errors),
            "dimension_score_coverage": score_pairs / expected_scores if expected_scores else None,
            "advice_usefulness": safe_mean(usefulness),
            "advice_safety_rate": sum(safety) / len(safety) if safety else None,
            "latency_p50_ms": percentile(latency, 0.50),
            "latency_p95_ms": percentile(latency, 0.95),
        }

    # Per-recipe metrics for the full product path make aggregate success unable to hide a weak domain.
    full_rows = [row for row in rows if str(row["variant"]) == "full"]
    by_recipe: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in full_rows:
        by_recipe[str(row["recipe_id"])].append(row)
    per_recipe: dict[str, Any] = {}
    for recipe_id, items in sorted(by_recipe.items()):
        ready_pairs = []
        abs_errors = []
        covered = 0
        expected = 0
        usefulness = []
        safety = []
        latency = []
        for row in items:
            h, m = row["human"], row["model"]
            if h.get("capture_ready") is not None and m.get("capture_ready") is not None:
                ready_pairs.append((bool(h["capture_ready"]), bool(m["capture_ready"])))
            hs, ms = h.get("scores", {}), m.get("scores", {})
            expected += len(hs)
            for dim, value in hs.items():
                if dim in ms:
                    covered += 1
                    abs_errors.append(abs(float(value) - float(ms[dim])))
            if row.get("advice_usefulness") is not None:
                usefulness.append(float(row["advice_usefulness"]))
            if row.get("advice_safe") is not None:
                safety.append(bool(row["advice_safe"]))
            if row.get("latency_ms") is not None:
                latency.append(float(row["latency_ms"]))
        per_recipe[recipe_id] = {
            "samples": len(items),
            "ready_accuracy": (sum(1 for h, m in ready_pairs if h == m) / len(ready_pairs)) if ready_pairs else None,
            "dimension_mae": safe_mean(abs_errors),
            "dimension_score_coverage": covered / expected if expected else None,
            "advice_usefulness": safe_mean(usefulness),
            "advice_safety_rate": sum(safety) / len(safety) if safety else None,
            "latency_p95_ms": percentile(latency, 0.95),
        }
    result["full_by_recipe"] = per_recipe

    full = result["variants"].get("full")
    if full:
        deltas: dict[str, Any] = {}
        for variant, metrics in result["variants"].items():
            if variant == "full":
                continue
            deltas[variant] = {}
            for key in ("ready_accuracy", "dimension_mae", "advice_usefulness", "latency_p95_ms"):
                a, b = full.get(key), metrics.get(key)
                if a is not None and b is not None:
                    deltas[variant][key] = b - a
        result["delta_vs_full"] = deltas
    return result


def format_pct(value: float | None) -> str:
    return "n/a" if value is None else f"{value * 100:.1f}%"


def format_num(value: float | None, digits: int = 3) -> str:
    return "n/a" if value is None else f"{value:.{digits}f}"


def markdown(summary: dict[str, Any], source: str) -> str:
    lines = [
        "# PhotoGuide empirical multimodal critic benchmark",
        "",
        f"Source: `{source}`",
        "",
        "| Variant | N | Recipes | Ready acc. | Dimension MAE | Score coverage | Advice usefulness | Advice safety | P50 ms | P95 ms |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for variant, m in summary["variants"].items():
        lines.append(
            "| " + " | ".join([
                variant,
                str(m["samples"]),
                str(m["recipe_count"]),
                format_pct(m["ready_accuracy"]),
                format_num(m["dimension_mae"]),
                format_pct(m["dimension_score_coverage"]),
                format_pct(m["advice_usefulness"]),
                format_pct(m["advice_safety_rate"]),
                format_num(m["latency_p50_ms"], 1),
                format_num(m["latency_p95_ms"], 1),
            ]) + " |"
        )
    lines += [
        "",
        "> This report only measures the supplied labeled rows. Synthetic/example fixtures are not empirical product evidence.",
    ]
    return "\n".join(lines) + "\n"


def enforce_thresholds(summary: dict[str, Any], thresholds: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    variants = summary.get("variants", {})
    required_variants = thresholds.get("required_variants", ["full"])
    for variant in required_variants:
        if variant not in variants:
            failures.append(f"missing required benchmark variant: {variant}")

    full = variants.get("full", {})
    checks = [
        ("minimum_total_full_samples", full.get("samples"), lambda actual, expected: actual >= expected, ">="),
        ("minimum_recipe_count", full.get("recipe_count"), lambda actual, expected: actual >= expected, ">="),
        ("minimum_ready_accuracy", full.get("ready_accuracy"), lambda actual, expected: actual >= expected, ">="),
        ("maximum_dimension_mae", full.get("dimension_mae"), lambda actual, expected: actual <= expected, "<="),
        ("minimum_dimension_score_coverage", full.get("dimension_score_coverage"), lambda actual, expected: actual >= expected, ">="),
        ("minimum_advice_usefulness", full.get("advice_usefulness"), lambda actual, expected: actual >= expected, ">="),
        ("minimum_advice_safety_rate", full.get("advice_safety_rate"), lambda actual, expected: actual >= expected, ">="),
        ("maximum_latency_p95_ms", full.get("latency_p95_ms"), lambda actual, expected: actual <= expected, "<="),
    ]
    for key, actual, compare, symbol in checks:
        if key not in thresholds:
            continue
        expected = thresholds[key]
        if actual is None:
            failures.append(f"{key}: metric missing")
        elif not compare(actual, expected):
            failures.append(f"{key}: actual {actual:.4f} must be {symbol} {expected}")

    required_recipes = thresholds.get("required_recipes", [])
    minimum_per_recipe = thresholds.get("minimum_samples_per_recipe")
    per_recipe = summary.get("full_by_recipe", {})
    for recipe_id in required_recipes:
        metrics = per_recipe.get(recipe_id)
        if metrics is None:
            failures.append(f"full benchmark missing recipe: {recipe_id}")
            continue
        if minimum_per_recipe is not None and metrics.get("samples", 0) < minimum_per_recipe:
            failures.append(f"{recipe_id}: {metrics.get('samples', 0)} samples < required {minimum_per_recipe}")

    generic = variants.get("generic_rubric")
    min_gain = thresholds.get("minimum_advice_usefulness_gain_vs_generic")
    if min_gain is not None:
        if not generic or full.get("advice_usefulness") is None or generic.get("advice_usefulness") is None:
            failures.append("cannot evaluate advice usefulness gain vs generic_rubric")
        else:
            gain = full["advice_usefulness"] - generic["advice_usefulness"]
            if gain < min_gain:
                failures.append(f"full advice usefulness gain vs generic_rubric {gain:.4f} < {min_gain}")

    single = variants.get("single_frame")
    max_mae_regression = thresholds.get("maximum_full_mae_regression_vs_single_frame")
    if max_mae_regression is not None:
        if not single or full.get("dimension_mae") is None or single.get("dimension_mae") is None:
            failures.append("cannot evaluate dimension MAE vs single_frame")
        else:
            regression = full["dimension_mae"] - single["dimension_mae"]
            if regression > max_mae_regression:
                failures.append(f"full dimension MAE regression vs single_frame {regression:.4f} > {max_mae_regression}")
    return failures


def self_test() -> None:
    fixture = [
        {
            "sample_id": "a",
            "recipe_id": "official.food",
            "variant": "full",
            "human": {"capture_ready": True, "scores": {"composition": 0.8, "lighting": 0.9}},
            "model": {"capture_ready": True, "scores": {"composition": 0.7, "lighting": 0.8}},
            "advice_usefulness": 1.0,
            "advice_safe": True,
            "latency_ms": 120,
        },
        {
            "sample_id": "b",
            "recipe_id": "official.food",
            "variant": "single_frame",
            "human": {"capture_ready": True, "scores": {"composition": 0.8}},
            "model": {"capture_ready": False, "scores": {"composition": 0.5}},
            "advice_usefulness": 0.5,
            "advice_safe": True,
            "latency_ms": 80,
        },
    ]
    summary = summarize(fixture)
    assert summary["variants"]["full"]["ready_accuracy"] == 1.0
    assert abs(summary["variants"]["full"]["dimension_mae"] - 0.1) < 1e-9
    assert summary["variants"]["single_frame"]["ready_accuracy"] == 0.0
    print("critic benchmark self-test PASS")


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate labeled PhotoGuide critic benchmark JSONL")
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--markdown-out", type=Path)
    parser.add_argument("--thresholds", type=Path, help="Optional release-threshold JSON; exits non-zero on failure")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return
    if args.input is None:
        parser.error("input JSONL is required unless --self-test is used")

    rows = load_rows(args.input)
    summary = summarize(rows)
    if args.thresholds:
        thresholds = json.loads(args.thresholds.read_text())
        failures = enforce_thresholds(summary, thresholds)
        summary["thresholds"] = {"source": str(args.thresholds), "passed": not failures, "failures": failures}
        if failures:
            for failure in failures:
                print(f"BENCHMARK GATE: {failure}", file=sys.stderr)
    else:
        failures = []
    encoded = json.dumps(summary, indent=2, ensure_ascii=False) + "\n"
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(encoded)
    else:
        print(encoded, end="")
    if args.markdown_out:
        args.markdown_out.parent.mkdir(parents=True, exist_ok=True)
        args.markdown_out.write_text(markdown(summary, str(args.input)))
    if failures:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
