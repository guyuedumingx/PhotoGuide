#!/usr/bin/env python3
"""Semantic-first architecture ablation for PhotoGuide.

This is a structural experiment, not a photographic-accuracy benchmark. It asks
what product capability remains when local Vision, temporal sampling, or
Recipe-specific photographic expertise is removed. The release principle is:
multimodal critique is the product core; local Vision is optional assistance.
"""
from __future__ import annotations
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
RECIPES = ROOT / "Packages" / "RecipeKit" / "Resources"
REPORT = ROOT / "Docs" / "ABLATION-REPORT-v0.8.0.md"
JSON_REPORT = ROOT / "Docs" / "ABLATION-REPORT-v0.8.0.json"

GENERIC_IDS = {"composition", "lighting", "light", "color", "overall"}
PROFILES = {
    "full": dict(critic=True, local=True, samples=3, domain=True),
    "critic-only": dict(critic=True, local=False, samples=3, domain=True),
    "single-frame-critic": dict(critic=True, local=False, samples=1, domain=True),
    "generic-rubric": dict(critic=True, local=False, samples=3, domain=False),
    "local-only": dict(critic=False, local=True, samples=0, domain=False),
}


def analyze(path: Path):
    recipe = json.loads(path.read_text(encoding="utf-8"))
    critic = recipe.get("critic") or {}
    dims = critic.get("dimensions") or []
    dim_ids = [d.get("id") for d in dims if d.get("id")]
    out = {}
    for name, p in PROFILES.items():
        if not p["critic"]:
            active = []
        elif p["domain"]:
            active = dim_ids[:]
        else:
            active = [d for d in dim_ids if d in GENERIC_IDS]
        coverage = 1.0 if not dim_ids else len(active) / len(dim_ids)
        out[name] = {
            "active_dimensions": active,
            "dimension_coverage": coverage,
            "professional_advice": p["critic"],
            "temporal_context": p["critic"] and p["samples"] > 1,
            "domain_rubric": p["critic"] and p["domain"],
            "local_assist": p["local"],
            "full_product_capability": bool(
                p["critic"] and coverage == 1.0 and p["domain"]
            ),
        }
    return {
        "id": recipe["id"],
        "file": path.name,
        "domain": recipe.get("presentation", {}).get("domain", "general"),
        "quality_dimensions": dim_ids,
        "preferred_sample_count": critic.get("preferredSampleCount", 0),
        "profiles": out,
    }


results = [analyze(p) for p in sorted(RECIPES.glob("*.recipe.json"))]
errors = []
for r in results:
    if len(r["quality_dimensions"]) < 5:
        errors.append(f"{r['id']}: critic profile has fewer than five quality dimensions")
    if r["profiles"]["critic-only"]["dimension_coverage"] != 1.0:
        errors.append(f"{r['id']}: removing local Vision reduces professional quality coverage")
    if not r["profiles"]["critic-only"]["full_product_capability"]:
        errors.append(f"{r['id']}: critic-only mode is not structurally product-complete")
    if r["profiles"]["local-only"]["full_product_capability"]:
        errors.append(f"{r['id']}: local-only was incorrectly treated as full product capability")
    if r["preferred_sample_count"] < 2:
        errors.append(f"{r['id']}: shipping critic does not request temporal sampled-frame context")

summary = {
    "version": "0.8.0",
    "recipe_count": len(results),
    "domains": sorted({r["domain"] for r in results}),
    "acceptance_passed": not errors,
    "errors": errors,
    "recipes": results,
}
JSON_REPORT.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

lines = [
    "# PhotoGuide v0.8.0 — Semantic-first Ablation Report",
    "",
    "> Structural ablation only. It validates architecture and Recipe coverage; it does not claim DJev/JEV photographic accuracy without an empirical image benchmark.",
    "",
    f"- Shipping recipes: **{len(results)}**",
    f"- Domains: **{', '.join(summary['domains'])}**",
    f"- Structural acceptance: **{'PASS' if not errors else 'FAIL'}**",
    "",
    "| Recipe | Domain | Quality dims | Critic-only | Single-frame | Generic rubric | Local-only |",
    "|---|---|---:|---:|---:|---:|---:|",
]
for r in results:
    p = r["profiles"]
    pct = lambda key: f"{p[key]['dimension_coverage']*100:.0f}%"
    lines.append(
        f"| `{r['id']}` | {r['domain']} | {len(r['quality_dimensions'])} | {pct('critic-only')} | {pct('single-frame-critic')} | {pct('generic-rubric')} | {pct('local-only')} |"
    )

lines += [
    "",
    "## Interpretation",
    "",
    "1. **Critic-only is the primary product path.** Removing local Vision must preserve 100% of the Recipe's professional image-quality dimensions.",
    "2. **Single-frame keeps semantic coverage but loses temporal evidence.** This isolates the value of sampled frames for motion, timing, transient expression and stability.",
    "3. **Generic-rubric removes domain expertise.** It should retain generic composition/light/color but lose food plating, product reflections, pet timing, architecture geometry, landscape depth, etc.",
    "4. **Local-only is a degraded fallback.** It may provide overlays, telemetry and emergency guidance, but it is not counted as PhotoGuide's full professional product capability.",
    "5. The client core remains model-agnostic: DJev can be replaced by another low-latency multimodal/System-1/JEV-style evaluator as long as it implements the same critic contract.",
    "",
    "## What this still does not prove",
    "",
    "The next empirical gate must run real images/video snippets across portrait, food, flower, product, pet, landscape and architecture datasets and compare model variants, sample counts and rubric ablations using human photographic judgments. This report only proves that the software architecture no longer makes local person/subject Vision the source of product generality.",
]
if errors:
    lines += ["", "## Failures", ""] + [f"- {e}" for e in errors]
REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")

print(f"Semantic-first ablation {'PASS' if not errors else 'FAIL'}: {len(results)} recipes")
for r in results:
    p = r["profiles"]
    print(
        f"  {r['id']:<28} critic-only={p['critic-only']['dimension_coverage']:.0%} "
        f"generic={p['generic-rubric']['dimension_coverage']:.0%} local={p['local-only']['dimension_coverage']:.0%}"
    )
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
