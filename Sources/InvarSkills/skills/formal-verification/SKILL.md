---
name: formal-verification
description: Check scoped production-derived models with swift-formal or a reviewed manual model and Invar. Use for implementation-model checks, node Verify model requests, or a project implementation stage. Record model scope, source correspondence and publication evidence.
---

# Implementation Model Verification

Use the reviewed requirements and independent conditions for the supplied scope. Return receipts, coverage and gaps to the caller. Use the [schema-2 evidence contract](../verify-project/references/project-verification.md) for project records.

| Assigned work | Start and return |
|---|---|
| Define conditions | Save named obligations and reviewed inputs. Return their locations and assumptions. |
| Verify the implementation model | Check the named obligations on the scoped production-derived model. Return checker evidence and exact source/model identities. |
| Validate correspondence | Use the supplied source/model identities and checker evidence. Run the correspondence work below on those exact bytes. Return validated correspondence or the uncovered behavior. |

Record model generation, regression tests and Source-to-Model Validation under their respective evidence domains.

Read the selected node and its callers, dependencies, tests and design at the requested snapshot. For a browser annotation, read every page of `read_verification_request` in its originating thread and check workspace, snapshot and entity identity. If the request expired, obtain a fresh selection. Identify the production decision that owns the property, its inputs, the intended result and what the property leaves outside scope.

## Define the obligation and select a model

Use the reviewed requirement as the source of the expected behavior. Keep the named, falsifiable obligation and reviewable inputs under `Verification/<subject>/` in the target repository. Reuse an existing condition when it still governs the captured code. Use the declaration name for a unique declaration or the selected entity ID otherwise. For a supported node check, express the precondition and postcondition in `properties.json`. Extract a production predicate only when the task authorizes source changes, then preserve the calling behavior and check its boundaries.

For a define-conditions request, save the specification and report the path, expected behavior, assumptions and rationale. Stop at definition. The separate model verification action runs the saved checks in Invar. A node may own a formal-only invar.json beside its specification or use a workspace configuration dedicated to that specification.

For a verification request, select the path supported by the source and the reviewed obligation:

- **Supported source.** Use the configured swift-formal check for the production entry. Bind the condition to its repository-relative source and the generated model. Record the verified domain and bounds.
- **Unsupported source or effects.** Retain the translator diagnostic. If the production behavior can be inspected and a reviewable model can represent the scoped obligation, derive an explicit model from the actual control, state, and effect boundaries. Use the configured Invar project check to run the applicable model check or proof. Label the model as manually derived and record its exact source and model inputs. If the necessary behavior or checker cannot be represented or executed, record the affected obligation and reason as incomplete.

For a stateful or concurrent obligation, map relevant request orderings, retries, and failure boundaries to transitions. Identify what persists or becomes observable at each transition and which guarantees come from the runtime or storage contract. Where a side effect crosses a commit boundary, model those steps separately and state the guarantee for attempts and delivery. Use actual checker results to report the verified properties and any counterexamples. Record any unmodeled transitions, external assumptions and bounds that limit the result.

## Check source correspondence

In correspondence mode, begin here with the recorded model check and its source/model inputs. Report missing or stale evidence to the caller. Trace the checked transitions through the captured production entry, its concrete implementation and the relevant runtime contracts. Exercise the actual affected path where possible. Record which transitions the test observed and which rely on a stated platform assumption or remain untested. Source review and runtime comparisons support the scope they establish. Claim passed Source-to-Model Validation only when semantic correspondence for the stated obligation is established for the same exact source and model inputs. Leave the correspondence assessment incomplete with the remaining gap when the evidence covers only samples or selected branches.

## Execute and publish against the selected snapshot

For an assigned check, submit the configured activity for that scope. Use the configured workspace daemon and obtain the indexed snapshot containing the exact captured inputs. When adding verification artifacts creates a new snapshot, resolve the original subject there, compare the relevant source and obligation, and report the new snapshot. Request a fresh selection if the subject or property changed. An archived snapshot can support scoped diagnostics when live capture fails. Record which snapshot was used and keep the live result and publication pending until their input binding is verified.

1. Submit `invar_plan` with the configuration path and a stable request key. Poll `invar_operation` to terminal state and read `invar_plan_info`. Match its workspace and snapshot to the selected target.
2. Submit `invar_run` with that plan ID, snapshot ID, entity ID and a distinct stable key. Poll its original operation. Retrieve `invar_report` and `invar_publication`; on disconnect reconcile the original operation.
3. Confirm that Explorer acknowledges a committed publication bound to that exact subject and snapshot. Report the checker result, source-correspondence result, and publication status explicitly with evidence references, assumptions and omissions. If publication is blocked, retain the valid result and report the concrete blocker and original operation when available. A saved report or completed checker run alone leaves Explorer publication unconfirmed.
