# Invar philosophy

Invar makes verification part of building software. The developer and the Agent start with the behavior the software should have, then accumulate evidence that the design and the implementation meet that contract. A project can enter this workflow before it has a specification, a source file or a C4 model.

## The development flow starts with the user's request

| Stage | What the developer and Agent establish | What advances the workflow |
| --- | --- | --- |
| Requirements and design | Write the governing `SPEC.md` and author any missing root `ARCHITECTURE.dsl`. Document user interaction in `DESIGN.md` where it applies. | Reviewed behavior and architecture contracts with identifiable requirements and verification obligations. |
| Specification Verification | Derive formal conditions from `SPEC.md`. Use TLA+ for transitions, concurrency and related properties, and Lean for invariants and mathematical contracts as applicable. Run the actual checkers through Invar before writing the affected production implementation. | Checker evidence for the required obligations and a review that the formalization expresses the user's requirements. |
| Implementation and tests | Implement the reviewed contract and exercise its actual user-facing and production execution paths. | Passing tests within their stated scope and implementation review. |
| Integration verification | Review actual production code and configuration against `ARCHITECTURE.dsl`. Run **Implementation Model Verification** and **Source-to-Model Validation** for the claimed behaviors. | Reviewed architecture reconciliation and current evidence for each required assessment support the verdict derived by Invar. |

Review every stage before advancing. A wrong requirement returns to requirements and design. A wrong formalization returns to specification verification. A code defect returns to implementation. A correspondence defect returns to the owner of the transformation or validation. Preserve prior evidence and rerun dependent checks whose inputs or assumptions changed.

## The skill is the workflow contract

The [verify-project skill](plugins/invar/skills/verify-project/SKILL.md) gives Codex and Claude the same ordered workflow, stage gates and review handoffs. Stage skills define their scoped work. The target repository owns the requirements, independent models, implementation, tests and review records. Invar binds those inputs to actual checker receipts and derives the verdict. A review, a successful process exit, a generated model and a proven property each carry their own meaning. Any gap in required proof, model correspondence, production coverage or review remains visible in the final result.

## Explorer connects the user and the Agent

| Participant | Responsibility |
| --- | --- |
| Developer | Review requirements and evidence, make decisions about the intended behavior, and initiate or inspect verification. |
| Agent | Follow the skill, prepare reviewable inputs in the target project, and use Invar over CLI or MCP to execute and observe the workflow. |
| Invar | Admit authorized work, run checkers on fixed inputs, retain original evidence, evaluate gates and publish results for the exact workspace and subject. |
| Architecture Explorer | Give the user a direct path from the Workspace to the specification, verification controls and results. Render the same requirements, stage status, evidence and limits that the Agent can query. |

The Workspace is an entry point at every stage, including when the next step is writing `SPEC.md`. A verification action opens its destination immediately and shows loading, progress or the reason it cannot proceed there. From an outcome, the user can navigate to the relevant requirement, code or model, original checker evidence and guarantee scope. The Agent can continue or reconcile the same operation through its immutable reference. The current view follows the committed publication, and earlier, failed and incomplete results remain available through their original bindings.
