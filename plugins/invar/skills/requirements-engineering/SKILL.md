---
name: requirements-engineering
description: Establish and maintain authorized, verifiable software requirements. Use for new or changed behavior, ambiguous requirements, conflicting specifications, or SPEC.md creation and revision.
---

# Requirements Engineering

Own the meaning, validity, and revision of requirements, not implementation boundaries or permission to expand work.

## Workflow
1. [Elicit](references/elicitation.md) stakeholder needs and sources. Reuse intent findings from scope-analysis if available.
2. [Analyze](references/analysis.md) semantic conflicts, scenarios, obligations and feasibility. Request scope-analysis for boundary or technical impact evidence; do not independently repeat it.
3. [Specify](references/specification.md) observable requirements and acceptance criteria.
4. [Validate](references/validation.md) against stakeholder intent; resolve material questions before authorizing affected work.
5. [Manage](references/management.md) baseline revisions, provenance and traceability.

## Integration
Use the [shared contract](../../references/requirements-and-scope.md). Return a Requirements Baseline to the caller. For implementation tasks, scope-management consumes this baseline and coordinates scope-analysis. If an analysis reveals a requirement question, resolve it here and return a revised baseline only when authorized. Do not invoke scope-management recursively.

Use SPEC.md where applicable; DESIGN.md covers UI/UX, architecture descriptions cover structure. Do not rewrite an approved specification to fit code. Lean/TLA+ and tests provide verification evidence, not stakeholder intent.

For small, clear tasks, existing authorized requirements or the direct request can suffice without running this skill. For specification-only work, do not implement. If scope-analysis is unavailable, return semantic findings and identify technical analysis gaps; do not pretend they were resolved.

## Result
Return baseline, sources, validation findings, unresolved decisions and authorization evidence. Never claim approval or verification without evidence.
