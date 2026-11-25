# Requirements Management

## Objective

Maintain the integrity of requirements as the software, stakeholder needs, and implementation evolve.

## Baseline and provenance

Use the existing approved specification as the baseline where available. Track stable identifiers, source, status, rationale, and relevant decision history proportionately. Keep proposed changes separate from authorized requirements. Use version control and existing project records rather than duplicating them without need.

## Change procedure

1. Identify the requested change and its authority. Distinguish requirement clarification, correction, addition, modification, removal, and implementation-only change.
2. Compare the proposal against the current baseline. Identify affected requirements and semantic contracts; request technical impact findings for consumers, artifacts, formal models, and tests from scope-analysis.
3. Analyze semantic conflicts and acceptance changes; consume SA findings for compatibility, migration and operational impact.
4. Return the proposed requirement revision to the caller; request technical impact findings from `scope-analysis` and let `scope-management` control the work boundary. Obtain explicit approval for material changes not already authorized. Necessary implementation changes do not automatically require a requirement revision.
5. Update the specification and related artifacts consistently once authorized. Preserve identifiers and history; mark superseded requirements instead of silently repurposing IDs.
6. Revalidate affected requirements and reverify affected implementation when applicable. Record actual evidence and remaining uncertainty.

## Bidirectional traceability

Maintain links proportional to risk:

- Stakeholder need → requirement → acceptance criteria → design/implementation → verification evidence.
- Implementation or test change → requirement or justified supporting obligation → authorized source.

Maintain requirement-side links; consume SA verification findings for missing requirements, orphaned changes, stale tests, and obsolete formal properties. A trace link is not proof of correctness.

## Rules

Never modify requirements merely to make failing implementation or tests pass. Distinguish an approved requirement change from a discovered mismatch. Do not mark a requirement implemented or verified without corresponding evidence. Report unrelated findings separately rather than turning them into new obligations.


## Handoff
Use [the shared contract](../../../references/requirements-and-scope.md). Record results in the Requirements Baseline or its proposed revision; report material unknowns without asserting authorization.
