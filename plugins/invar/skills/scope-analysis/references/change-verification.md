# Change Verification

## Inputs

Use authorized requirements, the scope statement, preserved contracts, impact findings, and the proposed plan or actual diff. Identify the baseline and separate pre-existing user changes from task changes. Do not revert or alter unrelated work.

## Bidirectional traceability

- Forward: map each requirement to planned or actual changes and verification evidence. Identify missing or partially implemented outcomes.
- Reverse: map every substantive change (including tests, configuration, generated files, and dependencies) to an authorized requirement or necessary supporting rationale. Identify unjustified changes.
- Preservation: check impacted contracts and non-goals for unintended behavioral changes. Evaluate changes collectively; a small diff is not inherently safe.

Use tests, static analysis, architecture checks, and formal verification where appropriate. A passing test is not proof of scope correctness; a formal proof establishes only the modeled property under its assumptions. Never weaken tests or requirements to fit the implementation.

## Results

For each acceptance criterion report passed, failed, not-run, or not-applicable, with evidence and justification for N/A. Summarize requirement coverage as satisfied, partial, missing, or unverified. For each substantive change report justified, unjustified, or unresolved. Distinguish proposed verification from checks actually executed. Record failures, coverage limitations, deviations, and required decisions.

Return findings and recommended corrective actions to the caller. Do not claim scope conformance when material requirements, changes, or preserved contracts remain unresolved. Never implement corrective changes in the SA role; return recommendations to the caller.


## Handoff
Use [the shared contract](../../../references/requirements-and-scope.md) for identifiers, classification, check status and baseline revisions. Return findings to the caller; do not authorize or apply changes.
