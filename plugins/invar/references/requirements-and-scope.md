# Shared collaboration contract — v2

The three Invar requirements and scope skills share this interface contract. It defines logical records, not mandatory YAML files. Preserve existing project conventions and IDs. A direct authorized request may be represented as a lightweight Requirements Baseline. Use task-local IDs only if no stable IDs exist.

## Ownership and dispatch

- Requirements Engineering (RE): requirement meaning, specification, validation, Requirements Baseline.
- Scope Analysis (SA): task interpretation, candidate boundary, technical impact, diff/coverage evidence; Analysis Findings and Verification Findings. No authorization or edits (read-only checks may be run if permitted).
- Scope Management (SM): Scope Baseline, execution and change control, completion decision. No independent technical analysis when valid SA findings exist.
- User or documented authority holder: authorization. A skill never grants itself approval.
- Caller (agent following AGENTS.md): dispatch and shared state; no recursive skill calls. RE or SM may request SA findings; SA returns questions to caller. SM routes requirement changes through RE. Reuse findings if still applicable; do not run all phases for every task.

## Common records

Every record has `id`, `revision`, `source_refs`, and relevant input baseline IDs/revisions. References identify actual request, specification, code, diff, logs or test results; unknowns remain explicit. For lightweight work these fields may be expressed inline. Do not invent commit IDs or evidence.

**Requirements Baseline (RE or direct-request adapter)**
- `requirements[]`: `id`, `outcome`, `source_refs`, `status` (proposed | authorized | superseded), `constraints[]`, `acceptance_criteria[]` (stable IDs, observable condition, planned method), `authorization_ref` (required for authorized), `open_questions[]`.
- `preserved_contracts[]`: ID, obligation, source. Existing behavior alone is evidence, not automatically a contract.
- `task_mode`: investigate | explain | plan | implement | review | specify (or explicitly authorized combination).
- `validation_findings[]`: semantic validation, unresolved issues. Authorization and validation are separate.

**Analysis Findings (SA)**
- `requirements_ref`, optional `scope_ref`, `inspected_state_ref` (commit plus working-tree snapshot or equivalent), `task_mode`, `intent_findings[]`.
- `candidate_boundary`: requested outcomes, discovery areas, implementation areas, impact areas, exclusions, preserved contract IDs. These dimensions need not be nested.
- `changes[]`: ID, target, classification, requirement/contract IDs, rationale, omission consequence, evidence refs, affected contracts.
- `evidence[]`, `unknowns[]`, `decision_requests[]`, `recommended_checks[]` (criterion/contract IDs and method).

**Scope Baseline (SM)**
- `requirements_ref`, `analysis_ref`, `authorization_refs`, `task_mode`, `initial_state_ref`, `in_scope_requirement_ids`, `exclusions`, `preserved_contract_ids`, `implementation_boundary`, `impact_boundary`, `required_check_ids`, `open_blockers[]`.
- `status`: proposed | active | superseded. Active only for authorized outcomes and sufficiently resolved decisions; unaffected authorized portions may be explicitly separated.
- `change_log[]`: reason, evidence, old/new revision, authorization reference where required. Component list is provisional, not a file whitelist.

**Verification Findings (SA)**
- `requirements_ref`, `scope_ref`, `actual_state_ref`, `diff_ref`.
- `coverage[]`: requirement/criterion ID, implementation or existing behavior ref, evidence, check status (passed | failed | not-run | not-applicable); optional requirement coverage summary (satisfied | partial | missing | unverified).
- `change_justification[]`: diff group, requirement/contract IDs, classification, evidence.
- `contract_checks[]`, `executed_checks[]`, `unresolved[]`, `unauthorized_changes[]`. Check status: passed | failed | not-run | not-applicable (justify N/A). Record actual command/method, relevant result and state checked; a trace link is not proof.

## Change classification (one primary class per substantive change)

| Class | Meaning | SM action |
|---|---|---|
| required | Directly satisfies an authorized requirement | Proceed within active boundary |
| supporting | Necessary to satisfy it or preserve an applicable contract | Proceed if constraints respected; record rationale |
| verification-only | Inspection/check or necessary test-only change | Execute if permitted; trace test edits and preserve test semantics |
| incidental | Unrelated issue discovered | Defer; no edit |
| expansion | New outcome, changed obligation, explicit exclusion/constraint crossed | Hold affected work; obtain authorization |
| uncertain | Insufficient evidence to classify | Analyze further; hold affected edit if material |

## Authority and evidence rules

Explicit authorization is required for expansion, breaking preserved contracts, or crossing explicit constraints. New files alone are not expansion. Never reinterpret an authorized requirement to excuse a failing implementation. Material ambiguity, conflicting instructions, unsafe actions or unknown necessity block affected work; continue independent authorized work. Reversible delegated implementation choices may proceed with a stated assumption. Preserve user changes. Do not weaken tests or acceptance criteria. Do not claim planned checks passed.

## Freshness and completion

Invalidate only affected findings when requirement/scope revision, relevant working state, diff, assumptions or test environment changes. Verify against the latest active baseline and actual final state. Reuse unaffected evidence with rationale. SM reports `complete` only if required outcomes and checks pass, changes are justified, contracts preserved, and no material blocker or unauthorized change remains; otherwise `partial`, `unverified`, or `blocked` with reasons. Stakeholder acceptance, if required, remains distinct from technical verification.
