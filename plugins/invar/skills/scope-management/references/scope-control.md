# Scope Control

Use the active Scope Baseline and SA change classifications in [the shared contract](../../../references/requirements-and-scope.md).

Before material edits, check that the change is required or supporting, or an authorized verification-only activity. If the finding is absent, stale, or uncertain, request targeted SA analysis. Do not repeat valid analysis.

- Allow required/supporting changes that respect the outcome and constraints. Record newly discovered necessary components in a revised implementation/impact boundary with evidence; this alone is not scope expansion.
- Defer incidental findings. Do not overwrite user changes, reformat unrelated files, add speculative abstractions, dependencies or compatibility layers.
- Route expansion to change-control. Hold affected work while authorization or material uncertainty is unresolved.
- When tests fail, request SA classification of the failure and its relationship to the change. Do not automatically repair unrelated failures or weaken tests.
- When requirements, design or relevant working state change, invalidate affected findings and request focused reanalysis. Preserve unaffected evidence.

Maintain the baseline and change log, not a second analysis record. Implementation remains the caller's responsibility under applicable project instructions.
