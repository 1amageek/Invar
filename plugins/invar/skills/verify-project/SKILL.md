---
name: verify-project
description: Orchestrate whole-project verification from SPEC.md through Specification Verification, Implementation Model Verification, Source-to-Model Validation and integration review. Use for project-wide correctness and complete verification reports. Scoped checks use their stage skills.
---

# Verify a project

Own the complete verification flow and its final verdict. Work in the target repository and preserve its original requirements. AGENTS.md owns global development rules; this skill owns the project verification stages. Read the [manifest and evidence contract](../../references/project-verification.md) before producing or aggregating records.

## Establish the scope

Read SPEC.md and DESIGN.md from cwd upward to the project root, then the more specific contracts governing the selected scope. Resolve contradictions before affected checking or changes. Extract the complete acceptance inventory with stable requirement IDs and exact governing-file hashes. Inventory production inputs and dependency boundaries. Map each requirement to its owning implementation scope, independent obligations and assumptions. Missing conditions remain open obligations; do not derive the intended guarantee from the code being checked.

## Execute the reviewed gates

| Stage | Responsibility and output | Pass condition | Return owner |
|---|---|---|---|
| requirements | Complete inventory, assumptions, production scope and a bound requirements review | Requirements are explicit, consistent and reviewed over exact governing inputs | requirements |
| specification | Run [Specification Verification](../verify-spec/SKILL.md) to produce independent TLA+/Lean checks and receipts | Every required specification assessment has checker evidence and a current passed review | requirements for a wrong requirement, or specification for an incorrect or incomplete formalization |
| implementation | Run [Implementation Model Verification](../formal-verification/SKILL.md) against models from the captured production inputs | Actual named conditions were checked, all required production inputs are covered, and the review passes | implementation for a code defect, or specification for a missing or wrong condition |
| correspondence | Run Source-to-Model Validation on the exact production sources and the same models used for Implementation Model Verification | Validated correspondence evidence and its review cover every requirement | correspondence for a transformation or validation defect, or implementation if the captured target is wrong |
| integration | Rebuild the complete report from original receipts and reviews; inspect cross-component assumptions and guarantees | All three assessments of every requirement and all five reviewed gates pass | The earliest owning stage identified by the finding |

Review each stage before using it as a passed prerequisite. Save review decisions, their exact input/receipt references, affected requirements and findings with returnTo owners. A requested revision invalidates that owner and dependent gates. Correct the cause and rerun only checks/reviews whose assumptions or inputs changed. Preserve previous evidence as history. Do not rewrite requirements merely to fit current code.

For new implementation, the necessary specification contracts and reviews must pass first. For an existing-code audit, downstream checks may collect diagnostics while an earlier gate is incomplete; keep those gates blocked and do not describe the audit as having passed the development flow.

## Preserve the evidence meaning

Each passed formal claim needs an executed successful checker receipt, a named obligation and its exact checked input. Implementation/correspondence evidence also binds production sources and model artifacts. Translation output is generation evidence; it does not establish an implementation property. Regression evidence keeps its test scope. Hashes and origin links establish identity, not semantic correspondence. Unsupported source, missing properties, exhausted resources and absent translation validation stay incomplete.

Store reviewed inputs and stage records in the target repository's Verification layout. Requirements-derived models remain separate from implementation-generated models. Use schema-2 manifests and receipts; [project_report.py](../../scripts/project_report.py) derives gates, production coverage, returnTo and the whole verdict. A review attests what was inspected; it cannot replace formal evidence or grant execution authority.

## Execute and publish

Use the configured Invar workspace daemon and host-approved project configuration. Submit invar_plan with a stable key, read the original operation to completion and inspect invar_plan_info. Verify its workspace, source snapshot, contract identity and scope. Submit invar_run with that plan, snapshot and subject entity, then read invar_report and invar_publication for that same operation. The session needs the approved planning/verification and project code/Lean execution capabilities. Reconcile existing operations after disconnect; do not create a new run merely to reopen a result.

Confirm the publication committed at the original Explorer subject/snapshot. Report the full inventory, the three assessment counts, each gate's status, the earliest returnTo, retained evidence and guarantee limits. A valid incomplete report uses exit 6 and remains visible; it does not satisfy project completion. Missing/changed receipts, malformed bindings or inconsistent verdicts are explicit invalid results. Stop with the unmet gate and concrete cause when required input, capability or supported semantics is unavailable.
