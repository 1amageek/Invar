---
name: verify-project
description: Establish missing requirements and architecture contracts for new or existing projects, then lead Specification Verification, Implementation Model Verification, Source-to-Model Validation and integration review. Use for project-wide development and correctness reviews. Scoped checks use their stage skills.
---

# Verify a project

Own the complete verification flow and its final verdict. Work in the target repository and preserve its original requirements. AGENTS.md owns global development rules; this skill owns the project verification stages. Read the [manifest and evidence contract](../../references/project-verification.md) before producing or aggregating records.

## Establish and review the requirements and architecture

Resolve the target workspace from cwd or the explicit workspace selection. Read applicable `SPEC.md` and `DESIGN.md` from cwd upward to the project root and inspect its root `ARCHITECTURE.dsl`. Fill gaps in the governing contracts before starting verification or changing production code in either a new or an existing project.

If the governing `SPEC.md` is missing, write it in the owning scope using the user's requirements and available project decisions. For an existing project, inspect the implementation, tests, and configuration to identify current behavior and discrepancies with the intended behavior. Record unresolved requirements for review. Preserve existing contract IDs and define stable IDs, observable acceptance conditions, failure behavior, and assumptions for new requirements.

As soon as the governing `SPEC.md` is complete and saved, open Explorer for the target workspace with `invar --workspace <workspace-root>`, or reuse its open Explorer session. Open **Specification** from the Workspace and confirm that it shows the saved requirements. Do this in the requirements stage, before Specification Verification and production implementation. Explorer can display the specification in a workspace that has yet to add source code or a C4 model. Record any startup or specification display failure in the requirements review.

If the root `ARCHITECTURE.dsl` is missing, create it with [generate-architecture](../generate-architecture/SKILL.md) using the specification and design decisions. When production code exists, use its entry points and effective configuration as evidence for the declared architecture. Preserve existing declarations and IDs, and review any discrepancies with the specification. Review both contracts and bind the requirements review to their exact files.

## Verify the specification and implementation

For a source-free project, use the Workspace entity as the subject, capture the specification-only snapshot, and configure the reviewed check with `stage: greenfieldSpecification`. When production code already exists, capture the current project snapshot and use the regular project check with the reviewed contracts and existing source inventory.

In either case, use [verify-spec](../verify-spec/SKILL.md) for independent TLA+/Lean obligations derived from `SPEC.md`. Reuse receipts and reviews whose governing inputs are intact. Run missing or outdated checks through Invar, inspect the checker evidence and bounds, and publish the reviewed specification assessment using the original receipt closure. Pass the requirements and specification gates before creating or changing production code.

Continue with the requested implementation work or the existing implementation under review, and run applicable tests and the structural review below. Compare the `ARCHITECTURE.dsl` contract with the actual entry points, data ownership, dependencies and effective configuration via [generate-architecture](../generate-architecture/SKILL.md). Review any differences against the original intent and return to the owning stage to correct them. Record the reconciliation in the integration review and bind it to the exact DSL files and implementation evidence. Submit the implementation and integration workflow through Invar on the snapshot that contains the reviewed contracts and implementation.

### Check implementation structure

For a Swift change or a project-wide Swift review, run [deslop](https://github.com/1amageek/deslop) before Implementation Model Verification. Run it for each Swift package or Xcode scheme in the reviewed scope. Use a fresh compiler index for the reviewed inputs and the relevant build configurations. Record any platform or conditional code outside that scope. For non-Swift code, use `deslop check --model` when the project has a frontend that produces a current deslop model for that scope. Record applicability in the implementation review.

Use `--allow <path>` when the repository has a reviewed allowlist. Preserve that baseline during the check. Bind the command, tool identity, build scope, exit status and retained diagnostics to the implementation review's exact inputs. Reuse a result only when those inputs, build configuration, tool and baseline still match.

| Result | Implementation review decision |
|---|---|
| Exit 0 | The structural check passes for the recorded scope. Continue with the applicable tests and model checks. |
| Exit 1 | Review the findings against the affected contracts. Record required changes with `returnTo: implementation`, fix the underlying structure and rerun the check. |
| Exit 2, missing tool or interrupted check | Keep the review incomplete. Resolve the execution prerequisite and rerun against the same inputs or capture the revised inputs. |

## Execute the reviewed gates

| Stage | Responsibility and output | Pass condition | Return owner |
|---|---|---|---|
| requirements | Complete inventory, assumptions, scope, `ARCHITECTURE.dsl` and a bound requirements review | Requirements and architecture are explicit and consistent, and both are reviewed over exact governing inputs | requirements |
| specification | Run [Specification Verification](../verify-spec/SKILL.md) to produce independent TLA+/Lean checks and receipts | Every required specification assessment has checker evidence and a current passed review | requirements for a wrong requirement, or specification for an incorrect or incomplete formalization |
| implementation | Review the implementation structure and run [Implementation Model Verification](../formal-verification/SKILL.md) against models from the captured production inputs | Applicable structural checks passed, actual named conditions were checked, all required production inputs are covered, and the review passes | implementation for a code defect, or specification for a missing or wrong condition |
| correspondence | Run Source-to-Model Validation on the exact production sources and the same models used for Implementation Model Verification | Validated correspondence evidence and its review cover every requirement | correspondence for a transformation or validation defect, or implementation if the captured target is wrong |
| integration | Rebuild the complete report and review implementation and configuration against the architecture contract | All three assessments of every requirement, the architecture comparison, applicable Explorer trace reviews, and all five reviewed gates pass | The earliest owning stage identified by the finding |

Review each stage before using it as a passed prerequisite. Save review decisions, their exact input and receipt references, affected requirements and findings with their owning return stage.

For each implemented C2 container in the reviewed scope with a source entry, open it in Explorer, enter C3, and follow the direct dependencies relevant to the reviewed contracts. Check their destinations and source evidence against the captured implementation and configuration. For a reference used in the review, follow it forward in Neighbors and back from its target in Impact. Confirm the same workspace, snapshot, original edge direction and source location throughout. Record the workspace and snapshot IDs, container, entry, dependency endpoints, evidence locations and observed result in the integration review. For an implemented container expected to have source but lacking a working entry, evidence path or available Explorer session, keep the review incomplete and identify the owner of the missing step. Record the applicable boundary and its basis for data stores, external containers and source entries with no relevant direct dependencies.

For new implementation, the necessary specification contracts and reviews must pass first. For an existing-code audit, downstream checks may collect diagnostics while an earlier gate is incomplete; keep those gates blocked and do not describe the audit as having passed the development flow.

For a scoped verification trial, keep the selected requirement and production boundary fixed. Use its stage skill to collect evidence and identify the first unmet stage for that requirement. Whole-project implementation or remediation requires its own task scope. If the selected scope is part of a project report, retain the complete inventory and report both the scoped finding and the project's earliest return owner.

## Continue through revisions

For authorized development or remediation, drive the loop in the active task. After a review or an Invar run, identify the earliest owning gate from the new findings or the latest valid report's `workflow.returnTo`. For each affected requirement, identify the failing behavior or missing evidence and take the next authorized corrective action in that gate. Treat an incomplete report (exit 6), a failed report (exit 5), or a published intermediate result as a reason to continue while a corrective action remains. Before production work begins, a source-free report with passed requirements and specification gates sends the Agent to implementation.

A revision reopens the owning gate and blocks dependent gates until their prerequisites pass again. Correct the cause while preserving the user's requirements. When captured inputs change, seal a new snapshot and bind the next run to it. Rerun affected checks and reviews, reuse evidence whose exact inputs and assumptions remain valid, and preserve prior runs as history. Read the resulting verdict and repeat, including when a later review reveals a problem in an earlier gate.

Update the user in the active conversation at the start, when a gate passes or reopens, when new evidence changes the remaining work, and at completion or a blocker. Name the gate, the verified and outstanding requirements or coverage, and the current action while work is underway. Include the bound Explorer report when available.

Continue while an authorized action can advance a required gate. Retry with changed inputs, a different supported validation route, or evidence that a transient failure has cleared. If progress requires a prerequisite the Agent cannot obtain within scope, report the gate, affected requirements, last valid evidence, and the specific prerequisite needed to resume. Use the current verdict for an audit that is limited to diagnosis.

## Preserve the evidence meaning

Each passed formal claim needs an executed successful checker receipt, a named obligation and its exact checked input. Implementation/correspondence evidence also binds production sources and model artifacts. Translation output is generation evidence; it does not establish an implementation property. Regression evidence keeps its test scope. Hashes and origin links establish identity, not semantic correspondence. Unsupported source, missing properties, exhausted resources and absent translation validation stay incomplete.

Store reviewed inputs and stage records in the target repository's Verification layout. Requirements-derived models remain separate from implementation-generated models. Use schema-2 manifests and receipts; [project_report.py](../../scripts/project_report.py) derives gates, production coverage, returnTo and the whole verdict. A review attests what was inspected. Checker receipts provide formal evidence.

## Execute and publish

Use the Invar workspace daemon and the project verification configuration. Submit invar_plan with a stable key, read the original operation to completion and inspect invar_plan_info. Verify its workspace, source snapshot, contract identity and scope. Submit invar_run with that plan, snapshot and subject entity, then read invar_report and invar_publication for that same operation. Reconcile existing operations after disconnect; do not create a new run merely to reopen a result.

Match the MCP launch budget to the budget declared in the project configuration before planning. When planning reports a budget or contract mismatch, compare the launch options and captured contract paths with the reviewed configuration. Capture the updated inputs in a new plan before retrying.

Confirm the publication committed at the original Explorer subject and snapshot. Open the governing specification and the published workflow report from the Explorer Workspace and check the reported stage decisions and return owner. A valid incomplete report can be published with its unmet gates visible. If publication is blocked, record the operation, cause and location of the retained report and reconcile that operation. Missing or changed receipts, malformed bindings and inconsistent verdicts make the result invalid.

Report the workflow complete only when the final valid report has `workflow.outcome == passed`, all five gates pass, and the bound Explorer publication is confirmed. Report the full inventory, three assessment counts, gate status, earliest return stage if any, retained evidence and guarantee limits.
