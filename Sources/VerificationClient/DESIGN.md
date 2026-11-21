# VerificationClient

## Purpose and Scope
SwiftPM public client library. Parent: [Invar](../../DESIGN.md). Child: [Session](Session/DESIGN.md).

## Responsibilities and Boundaries
Expose the same daemon-backed workflow to Codex/Claude MCP relays, CLI and programmatic clients. Depends on VerificationCore plus a private bounded native transport adapter; reuse public ArchitectureCore transport primitives where they meet the contract. No dependency on concrete Store, Runtime, Backends, Formal or a GUI.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Invar](../../DESIGN.md) | parent | Shared workspace daemon | Client boundary | No frontend scheduler |
| [Session](Session/DESIGN.md) | child | Typed requests/events | SDK implementation | Small Core protocols |
| [Core](../VerificationCore/DESIGN.md) | depends on | Immutable requests/views and ports | Public meanings | No backend-specific JSON interpretation |
| [Daemon](../VerificationDaemon/DESIGN.md) | depends on | IPC contracts | Remote service | Execution authority remains server-side |

## Architecture
```text
invar CLI / stdio MCP / programmatic client -> VerificationClient -> daemon
```

## Contracts and Invariants
Session owns the detailed interface/wire contract. All clients request the same ChangeVerificationView and exact evidence references. A thin client never writes the verification database or reconstructs a current verdict. ClientSessionTests, ClientProfileTests and ClientSessionRenewalTests exercise the actual bounded transport and original principal lifecycle.

## State, Ownership, and Lifecycle
Session actor owns active state; clients close subscriptions explicitly. The daemon owns changes, watches, queued/running jobs and durable history across disconnects.

## Failure, Concurrency, and Constraints
Use bounded asynchronous calls, current authority and explicit request outcomes. No source/log instruction is a tool grant. Offline artifact export reading, if provided, is explicitly offline and never accesses the live Store as a fallback.

## Verification and Change Impact
[Transition](../../Documentation/SDK-TRANSITION.md) owns release gates. Client/daemon integration tests must precede removing direct CLI paths. Recheck Core, Daemon, MCP and CLI together on protocol changes.

- [Formal](Formal/DESIGN.md): remote lower FormalEvidence reader implementation
