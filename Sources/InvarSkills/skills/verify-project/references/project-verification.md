# Project verification evidence contract

[verify-project](../SKILL.md) is the single owner of stage order, pass conditions and return behavior. verify-spec and formal-verification execute their assigned stages. This reference owns the data exchanged with the report builder and native assessment.

## Schema-2 manifest

The target repository owns the manifest, governing specifications, production inputs, models, conditions and reviews. Required fields are schemaVersion=2, title, inventory, productionInputs, requirements and receipts. reviews is an array of exact review references; absence means no reviewed gates. inventory identifies an exact governing source and its acceptance sections. Table inventories use existing first-column IDs. Bullet inventories use a declared prefix and one-based position. The extracted IDs must exactly equal the unique requirement rows. productionInputs is the complete declared production-source inventory, using repository-relative path/SHA-256 references; an empty inventory cannot complete implementation checking. governingDocuments retains additional exact authorities.

Each requirement has three assessments. The field names identify their stages in the manifest and report.

`architectureInputs` records exact path/SHA-256 references for root `ARCHITECTURE.dsl` and any local DSL fragments it uses. Supply the root even when the project has zero production sources. Absent architecture is incomplete at requirements. The verification run checks the references against its sealed inputs. The requirements review binds the architecture design and its validation. The integration review binds those declaration bytes plus production and relevant configuration references and reviews their correspondence. Specification checker receipts remain independently reusable when their requirements and model inputs have not changed.

| Field | Verification stage |
|---|---|
| `specification` | Specification Verification |
| `implementation` | Implementation Model Verification |
| `correspondence` | Source-to-Model Validation |

`claims` names unique receipt claims. Absent claims require an explicit uncovered reason. Requirement IDs, original statements and unmet entries remain in the final report. Grouping or filtering cannot change the inventory or verdict.

## Checker receipts and claims

Every receipt has schemaVersion=2, activity, command argv, executed, exitCode, inputs, outputs and claims. References contain path and sha256; absolute paths, repository escape, duplicate references and changed bytes reject the record. Receipts preserve actual process results and original checker artifacts.

| activity | method | Evidence meaning | Permitted checked phase |
|---|---|---|---|
| specificationCheck | modelCheck / proof | Independently specified TLA+/Lean obligation | specification |
| implementationCheck | modelCheck / proof | Named property checked on production-derived models | implementation |
| correspondenceCheck | translationValidation | Semantic relation of those same sources and models | correspondence |
| modelGeneration | generation | Model-generation observation, including unsupported inputs | Only a non-passed implementation observation |
| regression | test | Supporting test result | No formal phase |

Claims retain id, requirements, domain, outcome, scope and method. A passed formal claim additionally names one or more obligations: exact checked-input path/sha256 plus a nonempty selector for its theorem/property. Its receipt must have executed successfully with nonempty checked inputs and outputs. A successful translation command cannot stand in for an implementation check.

Specification domains start specification.; implementation domains start generatedModel. or source.; passed correspondence uses exactly translation.validated. Implementation/correspondence claims also name sourceInputs and modelInputs. Source references must belong to productionInputs and be actual receipt inputs; model references must be actual receipt inputs or outputs and distinct from the sources. For each requirement, correspondence must bind the same source/model sets as implementation checking. Passed implementation claims together cover the full production inventory.

Non-success outcomes are failed, unsupported, unknown or notVerified and retain their reasons. Missing properties or unsupported translation remain incomplete. A failed proof tactic alone is not a counterexample. A real violating witness belongs to the checker evidence. Receipt integrity, activity labels and review attestations do not certify a malicious producer; project workflows and checkers remain host-reviewed trust inputs.

## Stage review records

Each review reference identifies a JSON record with schemaVersion=1, stage, requirements, decision, summary, inputs and findings. Stages are requirements, specification, implementation, correspondence and integration. Decisions are passed, changesRequested or incomplete. Requirements are a nonempty subset of the inventory; overlapping reviews of the same stage/requirement reject aggregation rather than choosing a winner.

inputs binds the exact evidence inspected. All stages include the governing inventory source and governingDocuments. Specification includes its relevant checker receipts. Implementation includes productionInputs and its relevant receipts. Correspondence includes productionInputs and both implementation/correspondence receipts. Integration includes productionInputs, every checker receipt and all lower-stage review references. Hash binding makes later edits invalidate the review. Missing basis or review coverage makes the gate incomplete.

For the implementation stage, retain the code review's comparison, inspected inputs, coverage, checks, verdict and findings as supporting review evidence. Bind its record and any retained check outputs used for the decision in `inputs`. A blocking defect maps to `changesRequested` and the owning return stage. A material verification gap maps to `incomplete`. A supported review with no blocking findings can contribute to `passed` after the applicable formal assessments and other implementation prerequisites pass. Retain advisories in the supporting review evidence. Reuse the implementation review in integration only while its comparison, reviewed inputs and relevant assumptions still match.

A passed review has no findings. changesRequested has at least one finding containing requirementID, returnTo and reason. The return owner must be the reviewed stage or an earlier stage. A requested revision invalidates that owning gate and blocks its dependent gates. A review is an Agent attestation over recorded inputs. Formal claims require checker receipts.

## Derived report and completion

project_report.py independently validates references, producer activities, named obligations, production/model binding and review basis. It derives the five gates from evidence and accepted reviews. Earlier incomplete gates block later gate passage while preserving their observations. Missing data is incomplete; explicit failed obligations take precedence. The earliest unmet or revision owner is workflow.returnTo.

The standard Canvas document contains metadata.verificationReport with schemaVersion=2, the complete inventory/assessments, normalized evidence and reviews, productionInputs and derived workflow gates. Workflow-gate nodes expose blockers and return owners through the generic Canvas. Native ProjectReportAssessment recomputes claim outcomes, complete coverage, gate progression and the final verdict instead of trusting display labels.

Exit 0 requires every requirement's specification, implementation and validated correspondence assessment, full production coverage and all five current reviewed gates. Exit 5 retains failed obligations. Exit 6 retains an incomplete report and its return stage. Invalid/mutated evidence rejects publication and preserves the prior report. Runtime attempt copies, receipt/review closures and checker logs remain private retained evidence.

## Execution transport

A selected C4 subject owns Verification/Project/invar.json beside its declaration directory. The verification configuration binds the subject, argv, tool digests, governing inputs, report location and operational budget. Explorer enters the destination before availability reads; its confirmed action seals inputs, executes on a private copy and publishes to the original snapshot/subject.

Agent MCP uses invar_plan with that configuration and budget, then invar_run with the returned plan/snapshot/subject. Read the original operation, report and publication to completion. Reopening a report or reconnecting a client reads the original operation.

Use the Explorer Workspace entity as the project subject when starting a new project. Specification Verification uses a reviewed `SPEC.md` and `ARCHITECTURE.dsl` together with captured model/checker inputs. The optional `project.stage` value `greenfieldSpecification` requires a sealed input with no Swift or Rust sources and an empty production inventory in its report. After the independent evidence and specification review pass, integrate those receipts with a new implementation snapshot. The Workspace may show a valid incomplete project report before any production input exists.
