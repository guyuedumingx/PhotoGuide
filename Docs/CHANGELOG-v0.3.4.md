# PhotoGuide v0.3.4

## Core

- Added `InformationEffect` to `ActionDefinition`.
- Added `InformationPlanner` with explicit value-of-information scoring.
- Scheduler now proposes information-seeking Actions for UNKNOWN goals when their expected information value exceeds execution cost.
- HOLD / WAIT require prior evidence, preventing an initial unobserved scene from being treated as “just hold still”.
- Information actions are verified using post-action confidence/resolution changes.
- `ActionInstance.verificationGoals` prevents unrelated information slots from blocking verification.
- Added `PlanningUncertaintyModel` and `UtilityDistribution`.
- Short-horizon plans propagate uncertainty and rank by confidence-adjusted utility.
- Action plans expose expected utility, uncertainty and confidence-adjusted utility separately.
- Information actions are excluded from quality-oriented action sequences.
- Validator checks information-effect references and duplicate information effects.

## Recipe / UI

- Environmental portrait recipe upgraded to 20 actions, including explicit HOLD, WAIT and re-select-anchor information actions.
- Guidance UI has dedicated presentation for information actions.

## Verification

- GuidanceCore: 79 tests, 0 failures.
- RecipeKit: 6 tests, 0 failures.
- All Swift sources parsed successfully in the Linux validation environment.
