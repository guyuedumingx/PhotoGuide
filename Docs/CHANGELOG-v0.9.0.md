# PhotoGuide v0.9.0 — Reference + Question runtime

## Product change

The live intelligence path is reduced to one bounded comparison loop:

```text
Current Frame + Recipe References + One Question
                    ↓
                  DJev
                    ↓
          Choice / Score / Boolean
                    ↓
          Recipe-authored issue text
```

DJev no longer owns advice, actions, rationale or planning in the new Recipe path.

## Recipe

New/custom Recipes now carry:

- one or more reference images;
- bounded comparison questions;
- expected/matched answer definition;
- mismatch issue text;
- base question priority.

Recipe Studio supports reference-image creation, additional references, question editing, Choice/Score/Boolean configuration, priority editing, favorites, JSON import and local persistence.

The image-to-Recipe flow is structurally complete. Until real DJev is connected, it creates a valid shell from the selected reference image and generic starter questions; it does not pretend to infer photographic style.

## Question runtime

Added `QuestionRuntime` with:

- pending / issue / matched / skipped states;
- skip one question;
- restore one question;
- restore all skipped questions;
- matched-question low-frequency recheck;
- faster recheck for current mismatches;
- single issue slot ranked by `Recipe priority × mismatch severity`;
- strict rejection of invalid Choice values, out-of-range Scores and answer-type mismatches.

Camera/optical context invalidation clears stale answers while preserving user skips.

## Camera UI

- Live surface shows only the highest-priority Recipe-authored issue.
- Current issue can be skipped directly from the camera card.
- Control sheet shows all questions and their state and allows skip/restore.
- No question-mode action mapping exists.
- Continuous capture remains uninterrupted; there is no post-capture Review or critique report.

## Core boundary

New canonical files:

- `GuidanceCore/Runtime/VisualJudge.swift`
- `RecipeKit/RecipeQuestion.swift`
- `GuidanceUI/QuestionGuidanceCoordinator.swift`

Old SemanticCritic/Goal/Action code and bundled v0.8 Recipes remain only for compatibility. They are not the v0.9 new-Recipe contract.

## Validation

Structural ablation: `scripts/run-question-ablation.py`.

Release gate: `scripts/release-audit.py`.

Real DJev frame-vs-reference accuracy is intentionally not claimed until the model endpoint and held-out benchmark are available.
