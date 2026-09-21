# PhotoGuide v0.9.1 — Author order + swipeable camera issues

- Removed question `priority` from Recipe DTO and runtime contract.
- Removed mismatch `severity` and effective-priority ranking from QuestionRuntime.
- `questions[]` author order is now the only ordering rule.
- Runtime evaluates unseen questions in author order, then periodically rechecks in the same order.
- Camera keeps all current issues in author order and exposes them as a horizontal swipe surface.
- The selected issue can be skipped directly; selection does not alter Recipe order.
- Camera control sheet shows questions in Recipe order with no priority numbers.
- Recipe Studio adds move-up / move-down controls and removes the priority slider.
- Onboarding and Debug copy now describe comparison/order rather than action coaching or priority ranking.
- Core still has no action/advice/hint mapping and DJev remains bounded to Choice / Score / Boolean.
