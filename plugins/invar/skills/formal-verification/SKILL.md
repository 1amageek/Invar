---
name: formal-verification
description: Run Implementation Model Verification on scoped production code with swift-formal and Invar. Use for implementation-model checks, node Verify model requests, or the implementation stage of verify-project. Preserve unsupported inputs and snapshot-bound evidence.
---

# Implementation Model Verification

Whole-project orchestration belongs to [verify-project](../verify-project/SKILL.md). When assigned its implementation stage, use the reviewed requirements and independent conditions to check production-derived models. Return receipts, coverage and findings to the orchestrator. Record model generation, regressions and Source-to-Model Validation under their respective evidence domains. Use the [schema-2 evidence contract](../../references/project-verification.md) for project receipts and stage reviews.

Read the selected node and its callers, dependencies, tests and design at the requested snapshot. For a browser annotation, read every page of `read_verification_request` in its originating thread and check workspace, snapshot and entity identity. If the request expired, obtain a fresh selection. Identify the production decision that owns the property, its inputs, the intended result and what the property leaves outside scope.

Keep the reviewable specification under `Verification/<subject>/properties.json` in the target repository. For a unique declaration use its name as the subject. Use the selected entity ID for duplicate names or other node kinds. Reuse an existing specification. Express a falsifiable pre/postcondition against the supported production entry. For unsupported source, report the unsupported construct. Extract a production predicate only when the task authorizes source changes. Preserve the calling behavior and test its boundaries.

For a define-conditions request, save the specification and report the path, expected behavior, assumptions and rationale. Stop at definition. The separate model verification action runs the saved checks in Invar. A node may own a formal-only invar.json beside its specification or use a host-approved workspace configuration dedicated to that specification.

For a verification request, use the configured workspace daemon and a host-approved quantified formal check referencing the repository-relative source and specification. Obtain the indexed snapshot containing those exact bytes. When writing the specification creates a new snapshot, resolve the original symbol in it, compare the selected declaration and relevant inputs, and disclose the new snapshot. Request a new selection if identity or the property changed.

1. Submit `invar_plan` with the configuration path and a stable request key. Poll `invar_operation` to terminal state and read `invar_plan_info`. Match its workspace and snapshot to the selected target.
2. Submit `invar_run` with that plan ID, snapshot ID, entity ID and a distinct stable key. Poll its original operation. Retrieve `invar_report` and `invar_publication`; on disconnect reconcile the original operation.
3. Confirm that the committed Explorer publication binds that exact node in that snapshot. Report the property, repository path, execution, outcome, domain, assumptions, translation status and evidence reference. Identify counterexamples or incomplete runs explicitly. A generated-model proof supports only the stated model property; a claim about Swift behavior requires evidence for the translation.
