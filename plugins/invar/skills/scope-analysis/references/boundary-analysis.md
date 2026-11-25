# Boundary Analysis

Define scope in terms of outcomes and responsibilities before enumerating files.

| Dimension | Question |
|---|---|
| Requested | What outcome is authorized? |
| Discovery | What evidence must be inspected? |
| Implementation | What must change to achieve the outcome? |
| Impact | What may be affected and needs assessment? |
| Excluded | What is not authorized or necessary? |

For each proposed change, ask whether removing it would leave a requirement unmet or violate a preserved contract. If not, justify it through another authorized requirement or exclude it. This counterfactual is a heuristic, not a proof; evaluate interacting changes and alternative solutions together.

Identify affected responsibilities, interfaces, constraints, non-goals, and observable acceptance conditions. Preserve existing behavior unless the request or an applicable requirement authorizes a change. Do not confuse an explicit non-goal with an implementation assumption.

## Scope statement

- Goal and source of authorization
- In-scope behavior and deliverables
- Exclusions and non-goals
- Necessary implementation responsibilities (provisional)
- Preserved contracts and constraints
- Acceptance conditions and verification approach
- Assumptions and unresolved decisions

Return this candidate boundary to the caller. Baseline control belongs to SM; expansion approval belongs only to the user or documented authority holder.


## Handoff
Use [the shared contract](../../../references/requirements-and-scope.md) for identifiers, classification, check status and baseline revisions. Return findings to the caller; do not authorize or apply changes.
