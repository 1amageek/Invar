# VerificationClient.Session

## Purpose and Scope
**Implementation in progress; behavioral evidence and remaining gates are recorded in PROGRESS.md.** Own local daemon connection, typed requests and bounded subscriptions. Parent: [Client](../DESIGN.md). No children.

## Responsibilities and Boundaries
Implement Core client protocols through same-user IPC. No SQLite/file-source access, planning, verification execution, watch loop or verdict derivation. Closing a connection releases observation, not the daemon or durable work.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Client](../DESIGN.md) | parent | Thin public SDK | Transport boundary | Implemented SDK product |
| [Hosting](../../VerificationDaemon/Hosting/DESIGN.md) | depends on | IPC major 3 and workspace identity | Server authority | No compatibility handshake |
| [Changes](../../VerificationCore/Changes/DESIGN.md) | depends on | Change lifecycle | Agent workflow | Wait for open/sealed state |
| [Evidence](../../VerificationCore/Evidence/DESIGN.md) | depends on | Common view and evidence references | Read semantics | Exact immutable revisions |

## Architecture
```text
CLI / MCP relay / SDK client -> session client -> private Unix IPC -> daemon ports
subscription -> bounded event stream -> revisioned resync or shutdown
```

## Contracts and Invariants
Implement the small public Core ports listed in [Domain](../../VerificationCore/Domain/DESIGN.md). Session owns their wire transport and connection lifetime, not their domain semantics.

`LocalVerificationClient` supplies the implementation. Each mutating request carries a logical request id, idempotency key, canonical typed fingerprint and initial deadline. Before first admission, the transport obtains a daemon-issued request envelope binding that identity, workspace, fingerprint, daemon epoch, initial deadline and retention expiry. Preparation reserves no execution and is bounded by control limits; clients cannot renew an existing identity with a later deadline. Acceptance is durable before a receipt; initial receipt and changing job state are separate. Unknown delivery/restart never automatically resubmits as new work. Read queries have no execution side effect.

Protocol 3 binds the canonical workspace, the daemon engine and the actual server code identity. The transport admits peers from the same macOS user on a private local socket. No client profiles or capability negotiation are required.

Opening/sealing/planning may take time: return an accepted operation id, then report state/events. An Agent must observe baseline state open before editing and sealed revision before verification. A client request timeout detaches observation; it is not the worker's deadline or proof result. Resuming uses durable operation ids in the same workspace.

Subscriptions use daemon epoch plus monotonic persisted sequence, distinct from source snapshot ids, view revisions and AEX publication generations. Slow consumers receive RESYNC_REQUIRED with a bounded recovery query; no silent loss of evidence. `WorkspaceEventSubscription` owns its AsyncThrowingStream continuation; `shutdown` calls finish, cancels/drains reads and releases cursor pins. Returned pages own bounded values.

## State, Ownership, and Lifecycle
LocalVerificationClient owns connection admission, active one-request sockets and shutdown. Each call verifies the pinned server. Reconnecting uses the same endpoint and can read original receipts by ID.

## Failure, Concurrency, and Constraints
Bound frames, simultaneous calls, queued events/pages and client deadlines. Unknown protocol, changed engine, request conflict/expiry, missing receipt and unavailable daemon are distinct errors. Automatic activation respects the explicit user-stop latch.

## Verification and Change Impact
Planned `VerificationClientTests` **ID-01/04/05, IC-01, IE-04** exercise real sockets, two SDK/MCP clients, lost ACK/restart, incompatible versions, bounded streams, connection close while shared work continues. Recheck Hosting and frontend wrappers on wire changes.

### Request delivery and server identity

Envelope preparation and operation acceptance are separate public SDK steps. High-level operations report `OperationDeliveryError` containing the fixed prepared operation when acceptance delivery is uncertain, allowing receipt reconciliation without creating new work. There are no implicit mutating retries. Request/response sizes and simultaneous calls are bounded; shutdown closes owned sockets and finishes local observation without cancelling accepted work.

The production endpoint pins both kernel-reported signed code identity and executable-file digest, then checks the exact expected engine identity in the handshake. A matching on-disk path digest alone does not establish which code an already-running process loaded after a rebuild. Administrative stop after rebuilding uses the separate host-control contract; ordinary session connection does not weaken these checks to connect to a different engine.

AdministrativeSocket is the native administrative-only peer adapter. It compares the kernel UID/audit token/PID/birth identity to the private record established by the original validated server, then transfers its descriptor into LocalConnection for existing bounded framing. It deliberately does not validate the replacement disk image as the old running code. Ordinary LocalVerificationClient still requires its signed code, file digest and engine pins. Executable replacement, PID/birth/audit mutation, unsafe host-control record files and signal-driven detached shutdown have separate real-process regression coverage.

WatchControlling uses the same fixed prepare/accept protocol as other operations. Querying and stopping an existing watch use its workspace and original watch ID.

sourceHead exposes the separately committed source observation without private file bytes. currentView may deliberately retain a historical published view while sourceHead is uncertain or refers to newer source; the immutable view is not rewritten to claim current verification. These independent references are not an overall safety verdict.
