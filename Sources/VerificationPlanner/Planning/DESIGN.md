# VerificationPlanner.Planning

## Purpose and Scope
Own immutable verified-input planning and capability matching. Parent: [module](../DESIGN.md). No children.

## Responsibilities and Boundaries
Bind inventory, declared policy and oracle, tool identities, budget and backend mode. Never execute verification or silently replace unsupported inputs.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Public domain/module contracts | Component owner | Recheck direct consumers on changes |
| [Verification plan](../../../Documentation/VERIFICATION-PLAN.md) | coordinates with | Behavioral acceptance ownership | Test mapping | Mocks do not establish backend semantics |

## Architecture
```text
Validated input -> Planning -> immutable result or typed failure
```

## Contracts and Invariants
Implemented SDK revision. Plan preparation is a daemon-owned bounded operation, not CommandDriver work. It consumes sealed ChangeRevision/VerificationInput references and returns a persisted plan DAG with typed job/input/artifact references and exact resources and budgets. Plan does not execute user Lean/macros/build scripts; the backend owns execution.

Preserve exact input identity, separate execution/property/domain/translation/applicability, and propagate typed failures. Public API is protocol-based; concrete state does not escape its owner.

## State, Ownership, and Lifecycle
Invocation-local values or module-owned actors; no shared mutable global or target-specific synchronization. Active resource owners provide explicit shutdown/cleanup.

## Failure, Concurrency, and Constraints
Bound inputs and outputs according to the module contract. Cancellation/resource exhaustion is incomplete, never proof. External callbacks and I/O execute outside short Mutex scopes.

## Verification and Change Impact
Corresponding Invar test targets execute positive and negative behavior and invariant mutations. Changes recheck the parent module and its direct consumers; no completion claim comes from document structure.

[SDK transition](../../../Documentation/SDK-TRANSITION.md) owns current implementation facts, exact removal order and acceptance gates.

PlanBuilder binds formal job admission to FormalCheck.admissionMemoryMiB from the [Core domain contract](../../VerificationCore/Domain/DESIGN.md). Request-fit diagnostics and scheduler admission use the same sealed value.
