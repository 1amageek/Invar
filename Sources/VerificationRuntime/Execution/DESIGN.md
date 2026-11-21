# VerificationRuntime.Execution

## Purpose and Scope
Own process supervision and execution ports. Daemon.Workers composes the concrete private dispatch. Parent: [module](../DESIGN.md). No children.

## Responsibilities and Boundaries
Heavy formal/native tools run in owned monitored process groups with whole-attempt timeout and bounded output/scratch. Worker input is immutable and never a live source path.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Public domain/module contracts | Component owner | Recheck direct consumers on changes |
| [Verification plan](../../../Documentation/VERIFICATION-PLAN.md) | coordinates with | Behavioral acceptance ownership | Test mapping | Mocks do not establish backend semantics |

## Architecture
```text
Validated input -> Execution -> immutable result or typed failure
```

## Contracts and Invariants
Implemented SDK revision. Workers receive a minimum typed job, sealed access and engine/resource identities, not a full plan/inventory/stdout evidence blob. Keep current verified UID/start/group/session journals and exactly-once reap; native/user Lean require the explicit enforced sandbox. Heavy capture/hash/compile/graph-index preparation is also charged work. Deadline, resource cap, cancellation and cleanup remain separate.

Preserve exact input identity, separate execution/property/domain/translation/applicability, and propagate typed failures. Public API is protocol-based; concrete state does not escape its owner.

## State, Ownership, and Lifecycle
Invocation-local values or module-owned actors; no shared mutable global or target-specific synchronization. Active resource owners provide explicit shutdown/cleanup.

## Failure, Concurrency, and Constraints
Bound inputs and outputs according to the module contract. Cancellation/resource exhaustion is incomplete, never proof. External callbacks and I/O execute outside short Mutex scopes.

## Verification and Change Impact
Corresponding Invar test targets execute positive and negative behavior and invariant mutations. Changes recheck the parent module and its direct consumers; no completion claim comes from document structure.

[SDK transition](../../../Documentation/SDK-TRANSITION.md) owns current implementation facts, exact removal order and acceptance gates.
