# PhotoGuide v0.9.2 — Camera-first Ordered Question-core Ablation

> Structural only. Real frame-vs-reference accuracy is intentionally not claimed before DJev is connected.

- Acceptance: **PASS**
- Core: **Reference Images + ordered Recipe Questions + bounded JudgeAnswer**
- Judge outputs: **Choice / Score / Boolean only**

## A. Bounded System-1 output
Result: **PASS**. No free-form action/advice generation is required.

## B. Recipe owns comparison and order
Result: **PASS**. Questions are ordered data; no priority/action/hint field is required.

## C. Ordered question management
Result: **PASS**. Skip/restore and periodic recheck work without priority ranking or planning.

## D. Swipeable issue-only camera UI
Result: **PASS**. Current differences remain in Recipe order and can be switched horizontally.

## E. Necessity controls
Result: **PASS**. References, questions, and author order are functional product inputs.

## After DJev integration
Run empirical ablations on real current-frame/reference pairs: question-by-question agreement with human labels, recheck cadence, authored-order usability, and single-reference vs multi-reference consistency.
