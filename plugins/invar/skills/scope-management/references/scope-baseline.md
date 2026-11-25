# Scope Baseline

Consume the Requirements Baseline (or direct authorized request) and SA Analysis Findings. Check their references and freshness. If findings are missing, request only the necessary analysis; do not recreate it here.

1. Confirm task mode and authorization; no implementation for read-only requests.
2. Check that the proposed boundary covers every authorized requirement and preserves applicable contracts. Material gaps return to SA; semantic conflicts return to RE via caller.
3. Record the Scope Baseline using [the shared contract](../../../references/requirements-and-scope.md). Include exclusions, constraints, required checks, initial working state and existing user changes. Record authorized portions separately from blocked portions.
4. Activate the baseline only when its requirements are authorized and material decisions for the affected work are resolved. A candidate component list is not a rigid whitelist.
5. Keep baseline revisions and analysis references; update only through scope-control or change-control. Do not add product requirements here.

For a small bug fix, a few lines in the task context suffice: outcome, preserved behavior, proposed change, evidence/checks and authorization source.
