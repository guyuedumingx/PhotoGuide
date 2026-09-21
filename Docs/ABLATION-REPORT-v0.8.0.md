# PhotoGuide v0.8.0 — Semantic-first Ablation Report

> Structural ablation only. It validates architecture and Recipe coverage; it does not claim DJev/JEV photographic accuracy without an empirical image benchmark.

- Shipping recipes: **11**
- Domains: **architecture, food, landscape, nature, pet, portrait, product, travel**
- Structural acceptance: **PASS**

| Recipe | Domain | Quality dims | Critic-only | Single-frame | Generic rubric | Local-only |
|---|---|---:|---:|---:|---:|---:|
| `official.architecture` | architecture | 7 | 100% | 100% | 57% | 0% |
| `official.centered_portrait` | portrait | 7 | 100% | 100% | 57% | 0% |
| `official.closeup_portrait` | portrait | 7 | 100% | 100% | 57% | 0% |
| `official.environment_portrait` | portrait | 7 | 100% | 100% | 57% | 0% |
| `official.flower_macro` | nature | 7 | 100% | 100% | 57% | 0% |
| `official.food` | food | 7 | 100% | 100% | 57% | 0% |
| `official.landscape` | landscape | 6 | 100% | 100% | 67% | 0% |
| `official.pet` | pet | 6 | 100% | 100% | 50% | 0% |
| `official.product` | product | 7 | 100% | 100% | 57% | 0% |
| `official.solo_portrait` | portrait | 7 | 100% | 100% | 57% | 0% |
| `official.travel_portrait` | travel | 7 | 100% | 100% | 57% | 0% |

## Interpretation

1. **Critic-only is the primary product path.** Removing local Vision must preserve 100% of the Recipe's professional image-quality dimensions.
2. **Single-frame keeps semantic coverage but loses temporal evidence.** This isolates the value of sampled frames for motion, timing, transient expression and stability.
3. **Generic-rubric removes domain expertise.** It should retain generic composition/light/color but lose food plating, product reflections, pet timing, architecture geometry, landscape depth, etc.
4. **Local-only is a degraded fallback.** It may provide overlays, telemetry and emergency guidance, but it is not counted as PhotoGuide's full professional product capability.
5. The client core remains model-agnostic: DJev can be replaced by another low-latency multimodal/System-1/JEV-style evaluator as long as it implements the same critic contract.

## What this still does not prove

The next empirical gate must run real images/video snippets across portrait, food, flower, product, pet, landscape and architecture datasets and compare model variants, sample counts and rubric ablations using human photographic judgments. This report only proves that the software architecture no longer makes local person/subject Vision the source of product generality.
