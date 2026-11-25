# Intent Analysis

## Establish the task

- Identify the latest request, referenced prior decisions, existing specification, and applicable project instructions.
- Identify the task mode: investigate, explain, plan, implement, review, or specify (or an explicitly authorized combination). Do not infer implementation permission from an analytical request.
- Separate the problem, desired outcome, requested behavior, and suggested mechanism. Respect an explicitly mandated mechanism as a constraint.
- Identify the actors, affected use cases, current behavior, expected behavior, and relevant environment.

## Resolve ambiguity

Classify statements as explicit, entailed by evidence, assumed, contradicted, or unknown. Cite the source of material claims (specification section, code symbol, test, or user statement). Current implementation is evidence of behavior, not necessarily intended behavior.

Compare plausible interpretations. If they imply materially different outcomes, public contracts, data handling, or authorization, return a focused decision request to the caller. Do not select an interpretation merely because it is easier to implement. For reversible, low-risk details, use a reasonable assumption and disclose it when relevant.

## Output

- Authorized outcome and task mode
- Explicit requirements and constraints
- Inferred requirements with rationale
- Conflicts, unknowns, and decisions needed
- Candidate observable completion conditions (not approved requirements unless supported)


## Handoff
Use [the shared contract](../../../references/requirements-and-scope.md) for identifiers, classification, check status and baseline revisions. Return findings to the caller; do not authorize or apply changes.
