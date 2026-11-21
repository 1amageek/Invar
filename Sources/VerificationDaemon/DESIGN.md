# VerificationDaemon

## Purpose and Scope
SwiftPM daemon composition library. Parent: [Invar](../../DESIGN.md). Children: [Hosting](Hosting/DESIGN.md), [Workers](Workers/DESIGN.md).

## Responsibilities and Boundaries
Compose the sole workspace execution owner from public Runtime/Store/Explorer/Backend contracts. The executable delegates daemon/worker modes here; CLI/MCP use VerificationClient. No frontend owns a Store writer, watch loop or scheduler.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Invar](../../DESIGN.md) | parent | Workspace ownership | Composition root | Actual host composition |
| [Hosting](Hosting/DESIGN.md) | child | Lifecycle/security/IPC | Daemon behavior | Authority separate from residency |
| [Workers](Workers/DESIGN.md) | child | Private worker composition | Heavy operations | Enforced sandbox where required |
| [Core](../VerificationCore/DESIGN.md) | depends on | Shared domain ports | Composition contracts | No duplicate domain values |
| [Discovery](../VerificationDiscovery/DESIGN.md) | depends on | Observation/candidate analysis | Preparation | Bounded workers |
| [Planner](../VerificationPlanner/DESIGN.md) | depends on | Immutable plan generation | Preparation | No execution side effects |
| [Executable](../invar/DESIGN.md) | used by | Daemon and private worker composition | Entry modes | Client modes use Client |
| [Runtime](../VerificationRuntime/DESIGN.md) | depends on | Coordination/watch/admission | Shared tasks | No duplicate queue |
| [Store](../VerificationStore/DESIGN.md) | depends on | Durable ledger/views/outbox | Persistence | Format 2 only |
| [Explorer](../VerificationExplorer/DESIGN.md) | depends on | Source/Provider adapter | One shared index | No Explorer implementation edits |
| [Backends](../VerificationBackends/DESIGN.md) | depends on | Actual execution/evidence | Method meaning | Formal remains independent |

## Architecture
```text
invar daemon/worker entry -> VerificationDaemon -> Runtime/Core
                                            -> Store / Explorer / Backends
CLI/MCP -> VerificationClient --IPC--> Hosting
```

## Contracts and Invariants
One daemon per canonical workspace/user owns registered watches, changes, planning, work interests and durable evidence independent of Agent/UI lifetime. Children own detailed contracts. AEX registration/publication is not a verification scheduler; Model semantics stay in Formal.

## State, Ownership, and Lifecycle
DaemonRoot composes injected protocol implementations and owns explicit async startup/recovery/shutdown. Worker composition owns no global registry outside that root. No target-specific shared-state branch.

## Failure, Concurrency, and Constraints
Control plane remains responsive under bounded data/tool work. All work consumes one workspace resource policy and its recovery headroom. Unsupported capability and unknown delivery remain explicit.

## Verification and Change Impact
[Transition](../../Documentation/SDK-TRANSITION.md) owns ID/IC/IE/IV/IS acceptance gates and removals. Require lower contracts before replacing the current internal service. No new product/API is advertised by design files alone.

- [WorkspaceOperations](WorkspaceOperations/DESIGN.md): admitted capture, principal-owned changes and fixed preparation.

- [FormalQueries](FormalQueries/DESIGN.md): bounded private formal readers/pins

Provider Actions child: [ProviderActions](ProviderActions/DESIGN.md) owns confirmed source delivery and concrete SDK deduplication.
