# PhotoGuide v0.7.0 — Recipe / Perception Ablation Report

> Structural ablation. This validates dependency and fallback design; it does **not** substitute for an empirical image dataset on real iPhones.

- Shipping recipes: **11**
- Domains: **architecture, food, landscape, nature, pet, portrait, product, travel**
- Subject strategies: **human, saliency, scene**
- Structural acceptance: **PASS**

| Recipe | Domain | Strategy | Critical goals | Local-only | Geometry-only | Frame-only |
|---|---|---:|---:|---:|---:|---:|
| `official.architecture` | architecture | scene | 3 | 100% | 0% | 100% |
| `official.centered_portrait` | portrait | human | 5 | 100% | 100% | 0% |
| `official.closeup_portrait` | portrait | human | 4 | 100% | 100% | 0% |
| `official.environment_portrait` | portrait | human | 6 | 100% | 100% | 0% |
| `official.flower_macro` | nature | saliency | 6 | 100% | 83% | 17% |
| `official.food` | food | saliency | 6 | 100% | 83% | 17% |
| `official.landscape` | landscape | scene | 4 | 100% | 0% | 100% |
| `official.pet` | pet | saliency | 6 | 100% | 83% | 17% |
| `official.product` | product | saliency | 6 | 100% | 83% | 17% |
| `official.solo_portrait` | portrait | human | 5 | 100% | 100% | 0% |
| `official.travel_portrait` | travel | human | 6 | 100% | 100% | 0% |

## Acceptance invariants

1. Remote semantic AI may improve SOFT quality, but no shipping HARD/CORE readiness gate may depend on it.
2. Scene-only recipes (landscape / architecture) must remain fully decidable with frame metrics alone.
3. Non-human recipes must not depend on human body-pose dimensions.
4. Every HARD/CORE goal must have at least one corrective action or information-seeking action.
5. Losing subject geometry is allowed to degrade object/portrait recipes, but must not break scene-only recipes.

## What this experiment does not prove

The audit does not measure Vision precision/recall on flowers, food, pets, products, people or landscapes. That requires a labeled real-device benchmark. The repository therefore also defines a device benchmark contract so future camera captures can be scored by category, device, lens, light and failure mode rather than by anecdotal screenshots.
