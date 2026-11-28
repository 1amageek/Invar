---
name: requirements-engineering
description: Establish and maintain authorized, verifiable software requirements. Use for new or changed behavior, ambiguous requirements, conflicting specifications, or SPEC.md creation and revision.
---

# Requirements Engineering

Own the meaning, validity, and revision of requirements, not implementation boundaries or permission to expand work.

## Workflow
1. [Elicit](references/elicitation.md) stakeholder needs and sources. Reuse supplied intent findings.
2. [Analyze](references/analysis.md) semantic conflicts, scenarios, obligations and feasibility. Identify any technical boundary or impact evidence the caller needs to supply.
3. [Specify](references/specification.md) observable requirements and acceptance criteria.
4. [Validate](references/validation.md) against stakeholder intent; ask the user only about unresolved choices that change an observable acceptance result. Return the decision, rationale and authority per SPEC.md requirement ID.
5. [Manage](references/management.md) baseline revisions, provenance and traceability.

## Integration
Use the [shared contract](../scope-management/references/requirements-and-scope.md). Return a Requirements Baseline to the caller. Resolve requirement questions returned by the caller and revise the baseline when authorized.

Use SPEC.md where applicable; DESIGN.md covers UI/UX, architecture descriptions cover structure. Do not rewrite an approved specification to fit code. Lean/TLA+ and tests provide verification evidence, not stakeholder intent.

For small, clear tasks, existing authorized requirements or the direct request can suffice without running this skill. For specification-only work, do not implement. Return semantic findings and identify any remaining technical evidence gaps.

## Result
Return baseline, sources, validation findings, unresolved decisions and authorization evidence. Never claim approval or verification without evidence.
