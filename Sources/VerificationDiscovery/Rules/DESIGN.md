# VerificationDiscovery.Rules

## Purpose and Scope
Own the architecture-policy evaluator and deterministic discovery. Parent: [module](../DESIGN.md). No children.

## Responsibilities and Boundaries
One evaluator checks exact original raw facts for declared forbidden edges and cycles. It retains witnesses; incomplete coverage prevents a negative complete verdict.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Public domain/module contracts | Component owner | Recheck direct consumers on changes |
| [Verification plan](../../../Documentation/VERIFICATION-PLAN.md) | coordinates with | Behavioral acceptance ownership | Test mapping | Mocks do not establish backend semantics |

## Architecture
```text
Validated input -> Rules -> immutable result or typed failure
```

## Contracts and Invariants
Preserve exact input identity, separate execution/property/domain/translation/applicability, and propagate typed failures. Public API is protocol-based; concrete state does not escape its owner. Component-specific invariants are the responsibility/boundary contract above.

An empty selector match yields unknown, including complete recorded graphs. Duplicate identities and dangling fact endpoints are invalid inputs; no partial graph is substituted.

## State, Ownership, and Lifecycle
Invocation-local values or module-owned actors; no shared mutable global or target-specific synchronization. Active resource owners provide explicit shutdown/cleanup.

## Failure, Concurrency, and Constraints
Bound inputs and outputs according to the module contract. Cancellation/resource exhaustion is incomplete, never proof. External callbacks and I/O execute outside short Mutex scopes.

## Verification and Change Impact
Corresponding Invar test targets execute positive and negative behavior and invariant mutations. Changes recheck the parent module and its direct consumers; no completion claim comes from document structure.
