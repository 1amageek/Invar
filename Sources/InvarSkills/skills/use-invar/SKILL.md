---
name: use-invar
description: Start using Invar in a repository, and prepare or review its execution inputs. Use for first use, setup, missing project inputs, or an Invar verification request with an unprepared workspace.
---

# Use Invar

Resolve the target workspace from cwd or the explicit selection. Confirm the Invar MCP connection uses that workspace. For architecture browsing in Codex, open Explorer with the MCP installation’s `invar --workspace <workspace-root> --codex-browser` and open the returned local URL in the current chat. Reuse a working tab for the same workspace. For retained evidence, follow the original operation and snapshot.

## Prepare project verification inputs

Inventory these files against the requested subject and stage. Resolve referenced files and inspect their contents. For preparation or development work, prepare the execution configuration and runner when authorized. Report missing requirements, design, architecture and model inputs to the caller for authoring before planning. When the request is read-only, report each missing input and its owner.

| Input | If it is missing or unusable |
|---|---|
| Workspace-root `SPEC.md` and governing specifications | Locate existing requirements, including files referenced by the repository's design. Preserve the existing authority and requirement IDs. Identify requirements or acceptance conditions still needing a decision. For Explorer, require a root `SPEC.md` with the governing requirements or an accurate index to the existing authority so Explorer's Specification is usable. Keep the manifest inventory bound to the file and section that own the acceptance conditions. |
| Applicable `DESIGN.md` | Read existing design decisions and identify missing UI and interaction contracts relevant to the stage. |
| Root `ARCHITECTURE.dsl` and its local fragments | Identify missing declarations or fragments, mismatches with the governing requirements and unresolved links. Confirm the saved Map in Explorer. |
| Subject's `Verification/Project/invar.json` and the runner it references | Create or repair the configuration according to the [execution contract](../verify-project/references/project-verification.md#execution-transport). Use the indexed subject ID, reviewed runner argv, actual tool paths and digests, input contract paths, report location and a budget matching the MCP session. The runner must invoke the applicable checker and produce actual receipts. Retrieve the [report builder](../verify-project/scripts/project_report.py) over MCP and verify its digest when provisioning it. In a source-free workspace use the Workspace subject and the specification-only stage. |
| Stage-specific models, acceptance inventory and review inputs | Check that the required TLA+ or Lean inputs for the requested stage are available. Prepare the manifest inventory, architecture references and stage review inputs according to the [evidence contract](../verify-project/references/project-verification.md). Record checker receipts and outcomes when the checks actually run. |

## Check the contracts together in Explorer

Use one workspace and snapshot for the review. Trace the scoped acceptance IDs from the governing specification to the C1 system and C2 containers or relationships that own the behavior. Each in-scope behavioral declaration or relationship should cite the exact line of its governing requirement or design decision. Confirm the cited line and file digest against the same snapshot. Use the Map’s **Open components** action to follow each implemented runtime in scope through C3 to relevant C4 code and its source evidence. Review the actual binding and destination, even when the Map already renders. Return the exact unresolved or stale binding and its owner. Record the reason when a planned boundary, external service, or data store has no application entry.

When interaction scenarios are in scope, check that `SEQUENCES.dsl` extends the same architecture model and reuses its architecture IDs, relationship directions and governing requirement IDs. Open the scenario in Explorer and follow its evidence back to the same Map and source snapshot.

Set the verification configuration’s `project.subjectID` to the Explorer entity for the same architecture subject and bind the schema-2 manifest to the governing requirement IDs, architecture inputs and checked source/model bytes. When verification has been run, open its report from the original Explorer subject and trace the verdict to its recorded requirements and checker evidence. Use existing evidence when its binding still matches.

Review prepared contracts, including the configured runner and named obligations, before handing off. If the requested stage needs an unavailable subject, tool, input or decision, identify the exact missing prerequisite and its owner and report the stage as incomplete. Use the current snapshot after changing governing inputs. Report the source and snapshot for each observed link, the inputs reused or created, and any link that still blocks the requested next stage.
