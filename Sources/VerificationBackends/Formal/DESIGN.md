# VerificationBackends.Formal

## Purpose and Scope
Own finite and quantified library-backed formal verification. Parent: [module](../DESIGN.md). No children.

## Responsibilities and Boundaries
Use the replacement public Compiler/Validation/Evidence SDKs with verified pinned tools. Retain translation UNVALIDATED and original source bytes; unsupported frontend input is explicit.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Public domain/module contracts | Component owner | Recheck direct consumers on changes |
| [Verification plan](../../../Documentation/VERIFICATION-PLAN.md) | coordinates with | Behavioral acceptance ownership | Test mapping | Mocks do not establish backend semantics |

## Architecture
```text
Validated input -> Formal -> immutable result or typed failure
```

## Contracts and Invariants
For Swift source-only actions outside the complete scalar profile, parse the immutable original file and restrict extraction to syntax inside the selected node. Model supported arithmetic sites and conditional alternatives independently. Report source lines, model assumptions and local arithmetic checks, and keep surrounding framework behavior and any unmodeled computations outside the guarantee. Invalid syntax, empty extraction and resource limits remain explicit failures.

Source-only generation uses swift-formal in the resource-limited worker. The emitted TLA+ and Lean documents and their graphs share emitter byte ranges. Edges identify encoded blocks and branches. No theorem is checked. An unsupported input fails explicitly.

**Replacement SDK adapter implemented; behavioral evidence and remaining task gates are recorded in PROGRESS.md.** Consume compilation layout 2 and FormalEvidence structured inspection/checker results. Persist exact bundle references and per-obligation claims, origins, graph catalogs and trace identities; never parse human report detail to infer graph semantics or source mapping. Keep original-source profile restrictions and UNVALIDATED correspondence. Remove duplicate validation-then-generation and raw aggregate report folding when the new SDK replaces them.

Preserve exact input identity, separate execution/property/domain/translation/applicability, and propagate typed failures. Public API is protocol-based; concrete state does not escape its owner.

An isolated Invar worker injects an inherited-process-group runner into ModelVerifier/PropertyVerifier. The outer owner monitors aggregate RSS/process/CPU usage and kills the entire worker group before returning on every terminal path. Direct library callers retain isolated-tool ownership by default. Current resource measurements are sampled, not hard allocation maxima. Target sampling policy is selected and measured by the resource owner.

## State, Ownership, and Lifecycle
Invocation-local values or module-owned actors; no shared mutable global or target-specific synchronization. Active resource owners provide explicit shutdown/cleanup.

## Failure, Concurrency, and Constraints
Bound inputs and outputs according to the module contract. Cancellation/resource exhaustion is incomplete, never proof. External callbacks and I/O execute outside short Mutex scopes.

## Verification and Change Impact
Corresponding Invar test targets execute positive and negative behavior and invariant mutations. Changes recheck the parent module and its direct consumers; no completion claim comes from document structure.

[SDK transition](../../../Documentation/SDK-TRANSITION.md) owns current implementation facts, exact removal order and acceptance gates.

WorkerInvocation enforces the exact sealed formal job memory budget through the lower aggregate process-group RSS monitor. The configurable value and defaults are owned by [Core domain](../../VerificationCore/Domain/DESIGN.md). Actual tool integration records sampled peak RSS; exceeding the declared limit is an explicit resourceLimited attempt, without a larger-budget retry.
