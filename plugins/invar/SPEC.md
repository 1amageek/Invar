# Project verification reports

| ID | Requirement | Acceptance condition |
|---|---|---|
| PV01 | Complete acceptance inventory | Every identifier extracted from the exact governing specification has exactly one report requirement. Missing, additional or duplicate identifiers reject aggregation. |
| PV02 | Specification Verification | Each requirement retains its requirements-derived TLA+/Lean obligations, actual executions, explicit bounds and uncovered reasons. |
| PV03 | Implementation Model Verification | Each requirement retains verification conditions checked on models derived from exact production inputs. Unsupported, unknown and failed checks remain non-success outcomes. |
| PV04 | Source-to-Model Validation | Whole-project success requires evidence that the generated model preserves the source behavior relevant to every required claim. |
| PV05 | Phase ownership | A claim is usable only for its declared requirements and evidence domain. Regression evidence cannot replace specification, implementation or correspondence claims. |
| PV06 | Evidence identity | Exact specification, receipt inputs and receipt outputs are hash-checked within the selected repository before publication. Changed or missing bytes reject aggregation. |
| PV07 | Truthful completion | Every requirement needs successful specification, implementation and correspondence assessments. Empty inventories and missing evidence cannot yield a complete report. |
| PV08 | Observable whole-project result | Explorer displays the complete inventory and both verification phases with correspondence, including hidden or filtered unmet requirements. |

The execution authorities of existing tools remain their owners. The report builder consumes records and never executes workspace commands. Receipts preserve original commands, process outcomes, domains, scopes and hashes. The report integrity check does not certify an untrusted producer. The plugin workflow reviews requirements, Specification Verification, Implementation Model Verification, Source-to-Model Validation and integration evidence before publishing the whole result.

## Project verification action

| ID | Requirement |
|---|---|
| PA01 | A Map system/container starts the registered verify-project action, bound to one subject, workspace, snapshot and original manifest. The selected declaration directory owns Verification/Project/invar.json. Its project.subjectID must match the subject. |
| PA02 | A deliberate verification request runs against the configuration and inputs captured for its workspace snapshot. CLI, MCP and Explorer use the same execution rules. Edits can produce a new run without approval records or per-client permissions. |
| PA03 | The plan reads the complete captured input except its previous report and retained run output directory. A private writable copy owns execution; live repository sources are never used as execution inputs. Tool file identities are checked before and after. |
| PA04 | The project workflow runs Specification Verification and Implementation Model Verification, emits an immutable receipt manifest, and uses the plugin report builder to validate the complete acceptance inventory, receipt hashes, domains and evidence for Source-to-Model Validation. Missing or unsupported evidence remains incomplete. |
| PA05 | A valid completed report with verdict passed/failed/incomplete corresponds to process exit 0/5/6. A nonmatching exit, absent report, changed receipt/input or empty inventory cannot produce a checked result. Process deadlines, cancellation and restart preserve non-success. |
| PA06 | The existing durable Action ledger, scheduler, process journal and publication outbox own at-most-once admission, execution, cancellation and original-snapshot publication. A retry of reading or returning to a view never starts work. |
| PA07 | The whole report is published as a graph contribution and an outcome annotation bound to the original subject. The report keeps all three assessments and the complete inventory. Explorer displays the outcome and can reopen the original evidence. |

The verification daemon serves the local OS user through private Unix sockets. Repository-defined commands run in an OS-confined worker over a private snapshot copy, with network access denied and writes restricted to the attempt. Checks bind their tools and inputs to evidence. Requirements models and verification inputs remain repository-owned.

## Project workflow gates

| ID | Requirement |
|---|---|
| WG01 | verify-project owns whole-project orchestration. verify-spec and formal-verification own their assigned stages and do not duplicate or recursively restart the project workflow. AGENTS.md remains the global authority and is not modified by this plugin. |
| WG02 | Schema-2 project manifests retain the complete acceptance inventory, declared production inputs, checker receipts and stage reviews. The ordered stages are requirements, specification, implementation, correspondence and integration. Each gate needs its evidence and current review; a later observation cannot pass an earlier gate. |
| WG03 | A passed formal claim names an executed successful checker activity, its method and a nonempty named obligation bound to a checked input. Implementation and correspondence claims additionally bind exact production sources and model artifacts. Generation and regression records cannot supply a passed formal assessment. |
| WG04 | Implementation completion covers the entire declared production input inventory. Correspondence binds the same source/model inputs as implementation checking for each requirement. Hash identity alone does not establish semantic correspondence or certify a producer. |
| WG05 | Reviews bind exact governing inputs and relevant receipt references, cover declared requirements, record a decision and findings, and name the owning return stage. Missing review/evidence is incomplete; changed referenced bytes reject the result. Conflicting overlapping reviews are invalid rather than silently selected. |
| WG06 | A requested revision invalidates its owning gate and blocks dependent gates. The report preserves scoped observations and the earliest return stage. Existing-code audits may collect downstream diagnostics while gates remain blocked; implementation work cannot use such diagnostics to bypass the pre-implementation gate. |
| WG07 | Whole-project success requires every requirement's three assessments, complete production coverage and all five reviewed gates. The native assessment rejects absent or inconsistent claims, reviews and workflow gates. An incomplete valid report uses exit 6 and is never accepted as success. |
| WG08 | Requirements and design own the root `ARCHITECTURE.dsl` alongside `SPEC.md`. If absent, author it before proceeding, including in a source-free workspace. Both the requirements review and the integration review bind its exact captured declaration files. Integration compares that contract with production code and effective configuration. Missing architecture or applicable review keeps the project incomplete. |
| WG09 | For an authorized development or remediation task, the Agent resumes at the earliest owning stage from the latest report or a new review finding, corrects the cause, and reruns the affected checks and reviews. The Agent reuses evidence whose inputs and assumptions remain valid. The cycle continues while an authorized action can advance a required gate. Completion requires all gates to pass and the report to be confirmed at its bound Explorer snapshot. A blocked handoff identifies the unmet gate, affected requirements and the specific prerequisite to resume. |
| WG10 | The Agent reports progress in the active conversation at workflow start, when a gate passes or reopens, when evidence changes the remaining work, and at completion or a blocker. Each update identifies what has passed, what remains, and the current action when work is underway. |

## Architecture sequences

The generate-sequences skill captures the ordered interactions of a selected use case in the project's root SEQUENCES.dsl. The scenario reuses the architecture's element and relationship IDs, identifies the governing requirements, and cites the exact project material where known. Review the specification and trace the implementation when available. Architecture Explorer owns snapshot resolution, diagnostics, presentation and evidence navigation. A declared or source-supported scenario does not establish an observed execution or a verified property.

## MCP skill distribution

| ID | Acceptance condition |
|---|---|
| SK01 | The Invar stdio server advertises the official Skills extension and exposes the bundled skills with their complete manifests. The same source files supply the agent plugin. |
| SK02 | An MCP client can read each skill and all linked guidance or helper files from the server. The bytes and digests agree with the bundled content. The catalog includes only shipped skill files. |
| SK03 | Skills are static installation data. An MCP connection can discover them alongside the existing verification tools. Workspace content never adds or replaces a catalog entry. |
