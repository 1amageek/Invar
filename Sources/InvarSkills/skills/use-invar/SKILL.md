---
name: use-invar
description: Start using Invar in a repository, choose the right workflow, and prepare or review the files it needs. Use for first use, setup, missing project inputs, or an Invar verification request with an unprepared workspace.
---

# Use Invar

Resolve the target workspace from cwd or the explicit selection. Confirm the Invar MCP connection uses that workspace. Identify the requested operation before checking files.

| Request | Entry point |
|---|---|
| View the architecture or retained verification evidence | Open Explorer for the workspace or read the original result. Use the [Explorer startup procedure](../verify-project/SKILL.md#open-the-workspace-in-explorer) in Codex. |
| Prepare a project or run whole-project verification | Prepare the inputs below. For verification, follow [verify-project](../verify-project/SKILL.md) for Explorer startup and the reviewed gates. When called by that skill, return the readiness findings to it. |
| Verify a specification or implementation model in a selected scope | Use [verify-spec](../verify-spec/SKILL.md) or [formal-verification](../formal-verification/SKILL.md) for that scope and check their input requirements. |

## Prepare project verification inputs

Inventory these files against the requested subject and stage. Resolve referenced files and inspect their contents. For preparation or development work, create or repair missing inputs within the authorized scope before planning. When the request is read-only, report each missing input and its owner.

| Input | If it is missing or unusable |
|---|---|
| Workspace-root `SPEC.md` and governing specifications | Locate existing requirements, including files referenced by the repository's design. Preserve the existing authority and requirement IDs. Use [requirements-engineering](../requirements-engineering/SKILL.md) to establish missing requirements and acceptance conditions from authorized decisions. Provide a root `SPEC.md` with the governing requirements or an accurate index to the existing authority so Explorer's Specification is usable. Keep the manifest inventory bound to the file and section that own the acceptance conditions. |
| Applicable `DESIGN.md` | Read existing design decisions. Write or update the UI and interaction contract when that design is in scope. |
| Root `ARCHITECTURE.dsl` and its local fragments | Create or reconcile the contract with [generate-architecture](../generate-architecture/SKILL.md), using requirements, known design decisions and existing implementation/configuration. Review the saved declarations and confirm the resulting Map in Explorer before project verification. |
| Subject's `Verification/Project/invar.json` and the runner it references | Create or repair the configuration according to the [execution contract](../verify-project/references/project-verification.md#execution-transport). Use the indexed subject ID, reviewed runner argv, actual tool paths and digests, input contract paths, report location and a budget matching the MCP session. The runner must invoke the applicable checker and produce actual receipts. Retrieve the report builder from the verify-project MCP resource and verify its digest when provisioning it. In a source-free workspace use the Workspace subject and the specification-only stage. |
| Stage-specific models, acceptance inventory and review inputs | Derive the required TLA+ and Lean inputs with the applicable stage skill. Prepare the manifest inventory, architecture references and stage review inputs according to the [evidence contract](../verify-project/references/project-verification.md). Record checker receipts and outcomes when the checks actually run. |

## Check the contracts together in Explorer

Use one workspace and snapshot for the review. Trace the scoped acceptance IDs from the governing specification to the C1 system and C2 containers or relationships that own the behavior. Each in-scope behavioral declaration or relationship should cite the exact line of its governing requirement or design decision. Confirm the cited line and file digest against the same snapshot. Use the Map’s **Open components** action to follow each implemented runtime in scope through C3 to relevant C4 code and its source evidence. Review the actual binding and destination, even when the Map already renders. Resolve missing or stale bindings with [generate-architecture](../generate-architecture/SKILL.md). Record the reason when a planned boundary, external service, or data store has no application entry.

When interaction scenarios are in scope, use [generate-sequences](../generate-sequences/SKILL.md). Its `SEQUENCES.dsl` extends the same architecture model and reuses the architecture IDs, relationship directions and governing requirement IDs. Open the scenario in Explorer and follow its evidence back to the same Map and source snapshot.

Set the verification configuration’s `project.subjectID` to the Explorer entity for the same architecture subject and bind the schema-2 manifest to the governing requirement IDs, architecture inputs and checked source/model bytes. When verification has been run, open its report from the original Explorer subject and trace the verdict to its recorded requirements and checker evidence. Use existing evidence when its binding still matches.

Review prepared contracts, including the configured runner and named obligations, before handing off. If the requested stage needs an unavailable subject, tool, input or decision, identify the exact missing prerequisite and its owner and report the stage as incomplete. Use the current snapshot after changing governing inputs. Report the source and snapshot for each observed link, the inputs reused or created, and any link that still blocks the requested next stage.
