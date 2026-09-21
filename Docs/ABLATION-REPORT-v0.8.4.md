# PhotoGuide v0.8.4 — Product-core Ablation

> Structural ablation only. No DJev/JEV photographic-accuracy claim is made before a real held-out benchmark is run.

- Acceptance: **PASS**
- Shipping Recipes checked: **11**
- Product surfaces under test: **live shooting guidance + Recipe assets**

## A. Remove post-capture review/report

Result: **PASS**. The shutter and live-tip surface remain while CaptureReview/CriticReport are absent.

## B. Decouple capture from persistence

Result: **PASS**. The shutter lock is released before Photo Library persistence completes, so saving cannot become the workflow gate.

## C. Recipe asset independence

Result: **PASS**. Reference-image generation, favorites, JSON import, custom editing and persistence share RecipeDTO; only the image-understanding generator is replaceable.

## D. Remove local control / legacy Goal-Action graph

All 11 shipping Recipes retain **100% critic-dimension coverage** in critic-only mode. A generated/custom Recipe can contain zero nodes/goals/actions.

## E. Remove Recipe-specific rubric

**11/11** shipping Recipes lose at least one domain-specific quality dimension when reduced to the generic rubric set. This is the control showing that Recipe carries real domain knowledge rather than being decorative metadata.

## Still required after DJev integration

Run the empirical held-out benchmark on real frames/images: full Recipe vs generic rubric, one frame vs sampled frames, and DJev vs future System-1/JEV-style providers. Compare advice usefulness and dimension agreement against human photographic judgments.
