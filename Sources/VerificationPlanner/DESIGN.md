# VerificationPlanner

## Purpose and Scope
Compose sealed inventory, explicit obligations, tool identities and budgets into a validated job DAG. Native SwiftPM module. Parent: [Invar](../../DESIGN.md).

- [Planning](Planning/DESIGN.md)

## Responsibilities and Boundaries
Compose sealed inventory, explicit obligations, tool identities and budgets into a validated job DAG. Product-level requirements and remaining gates are owned by [Invar](../../DESIGN.md) and [support status](../../Documentation/SUPPORT.md). Detailed implementation contracts belong to the children below.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Invar](../../DESIGN.md) | parent | System composition and authority | Module boundary | Preserve dependency direction |
| [Planning](Planning/DESIGN.md) | child | Component public contract | VerificationPlanner composition | Recheck module consumers after contract changes |
| [VerificationCore](../VerificationCore/DESIGN.md) | depends on | Plan/input/capability values | Direct module boundary | Recheck at SDK cutover |
| [VerificationDaemon](../VerificationDaemon/DESIGN.md) | used by | Preparation composition | Direct module boundary | Recheck at SDK cutover |

## Architecture
```text
Composition -> VerificationPlanner public contracts -> owned components -> immutable result / typed failure
```

## Contracts and Invariants
Planning does not execute user code or install runtimes. Unsupported/missing environments remain visible. Only exact captured source/oracle/corpus bytes enter a plan.

## State, Ownership, and Lifecycle
Immutable Sendable domain values cross boundaries. Components own mutable actor state, process/file/database handles and explicit shutdown. The supported host is macOS 27 arm64; no WASM/Embedded state branch is introduced.

## Failure, Concurrency, and Constraints
Errors remain explicit. Resource and lifecycle limits are specified by the owning child contract; cancellation drains owned work before terminal publication. Product runtime acquisition is outside normal verification.

## Verification and Change Impact
PlanContractTests, SchedulerTests and Tools/verify-explorer-daemon.py. [Acceptance ownership](../../Documentation/VERIFICATION-PLAN.md) separates actual evidence from unmet requirements. Recheck this composition and direct consumers when a child changes its public contract.
