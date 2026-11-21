# VerificationCore.Assessment

## Purpose and Scope
Own pure fail-closed assessment. Parent: [module](../DESIGN.md). No children.

## Responsibilities and Boundaries
A run is acceptable only when every required approved obligation has matching complete adequate evidence. Preserve model-versus-source scope, no majority vote or vacuous success.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Public domain/module contracts | Component owner | Recheck direct consumers on changes |
| [Verification plan](../../../Documentation/VERIFICATION-PLAN.md) | coordinates with | Behavioral acceptance ownership | Test mapping | Mocks do not establish backend semantics |

## Architecture
```text
Validated input -> Assessment -> immutable result or typed failure
```

## Contracts and Invariants
Implemented SDK revision. Assess the shared committed ChangeVerificationView through Evidence associations, preserving independent axes and exact scoped input/closure comparisons. No frontend or renderer derives a separate current verdict. Existing domain separation, nonvacuity, original-witness replay and fail-closed requirements remain.

Preserve exact input identity, separate execution/property/domain/translation/applicability, and propagate typed failures. Public API is protocol-based; concrete state does not escape its owner.

ProjectReportAssessment consumes schema-2 reports under the [project evidence contract](../../../plugins/invar/references/project-verification.md). It recomputes claim outcomes, declared production coverage and the ordered reviewed gates through the invocation-local ProjectWorkflowAssessment helper. Absent claims, inconsistent source/model bindings, incomplete reviews or gate/verdict disagreement cannot establish whole-project success. Raw receipt and review-file integrity belongs to the pinned builder at the [Project execution boundary](../../VerificationBackends/Project/DESIGN.md); native consistency checking does not certify arbitrary checker producers.

The requirements gate needs a root architecture declaration. Native assessment checks exact architecture references against the inputs of the requirements and integration reviews, in addition to the report builder's other review bindings.

## State, Ownership, and Lifecycle
Invocation-local values or module-owned actors; no shared mutable global or target-specific synchronization. Active resource owners provide explicit shutdown/cleanup.

## Failure, Concurrency, and Constraints
Bound inputs and outputs according to the module contract. Cancellation/resource exhaustion is incomplete, never proof. External callbacks and I/O execute outside short Mutex scopes.

## Verification and Change Impact
Corresponding Invar test targets execute positive and negative behavior and invariant mutations. Changes recheck the parent module and its direct consumers; no completion claim comes from document structure.

Replay compares two retained runs of the same sealed plan. A previous violation that does not recur is unreproduced, never erased. Incomplete outcomes are inconclusive; comparisons do not promote the new run to source proof.

Native replay requires an opaque backend reproductionKey. A changed counterexample input/classification is not a reproduced original violation. Missing historical keys yield inconclusive; a new completed non-violation leaves the previous violation unreproduced. Structural replay additionally preserves exact witness fact IDs.

[SDK transition](../../../Documentation/SDK-TRANSITION.md) owns current implementation facts, exact removal order and acceptance gates.
