# VerificationClient.Session

## Purpose and Scope
**Implementation in progress; behavioral evidence and remaining gates are recorded in PROGRESS.md.** Own local daemon connection, typed requests and bounded subscriptions. Parent: [Client](../DESIGN.md). No children.

## Responsibilities and Boundaries
Implement Core client protocols through authenticated same-user IPC. No SQLite/file-source access, planning, verification execution, watch loop or verdict derivation. Closing a connection releases observation, not the daemon or durable work.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Client](../DESIGN.md) | parent | Thin public SDK | Transport boundary | Implemented SDK product |
| [Hosting](../../VerificationDaemon/Hosting/DESIGN.md) | depends on | IPC major 2 and principals | Server authority | No compatibility handshake |
| [Changes](../../VerificationCore/Changes/DESIGN.md) | depends on | Change lifecycle | Agent workflow | Wait for open/sealed state |
| [Evidence](../../VerificationCore/Evidence/DESIGN.md) | depends on | Common view and evidence references | Read semantics | Exact immutable revisions |

## Architecture
```text
CLI / MCP relay / SDK client -> session client -> private Unix IPC -> daemon ports
subscription -> bounded event stream -> revisioned resync or shutdown
```

## Contracts and Invariants
Implement the small public Core ports listed in [Domain](../../VerificationCore/Domain/DESIGN.md). Session owns their wire transport and connection lifetime, not their domain semantics.

`LocalVerificationClient` supplies the implementation. Each mutating request carries a logical request id, idempotency key, canonical typed fingerprint and initial deadline. Before first admission, the transport obtains a daemon-issued authenticated request envelope binding that identity, principal/workspace, fingerprint, authorization epoch, initial deadline and retention expiry. Preparation reserves no execution and is bounded by control policy; clients cannot renew an existing identity with a later deadline. Acceptance is durable before a receipt; initial receipt and changing job state are separate. Unknown delivery/restart never automatically resubmits as new work. Read queries have no execution side effect.

Handshake binds protocol major 2, canonical workspace, daemon epoch, schema/engine identity, peer-authenticated principal and granted policy revision. Filesystem/socket permission and matching workspace strings alone do not grant execution. Read, change tracking, planning, execution, source/value inspection and administration are separate permissions. MCP tool arguments cannot widen the startup scope/policy.

Opening/sealing/planning may take time: return an accepted operation id, then report state/events. An Agent must observe baseline state open before editing and sealed revision before verification. A client request timeout detaches observation; it is not the worker's deadline or proof result. Resuming uses durable operation ids under current authority.

Subscriptions use daemon epoch plus monotonic persisted sequence, distinct from source snapshot ids, view revisions and AEX publication generations. Slow consumers receive RESYNC_REQUIRED with a bounded recovery query; no silent loss of evidence. `WorkspaceEventSubscription` owns its AsyncThrowingStream continuation; `shutdown` calls finish, cancels/drains reads and releases cursor pins. Returned pages own bounded values.

## State, Ownership, and Lifecycle
A shared session actor owns credential/nonce, connection state, request reservations and subscriptions. Value copies share that actor; no duplicated rate-limit counters. Credentials are private and never placed in model/source/graph/report data. Explicit close invalidates the session and finishes local streams without stopping shared jobs. Reconnect creates a new session, rechecks authority and uses durable ids for reconciliation.

## Failure, Concurrency, and Constraints
Bound frames, simultaneous calls, queued events/pages, retry attempts and client deadlines by negotiated policy. Unknown major, changed engine, revoked grant, request conflict/expiry, missing receipt and unavailable daemon are distinct errors. Administrative `start` is an explicitly authorized local bootstrap of the configured daemon binary; it cannot be sent to a nonexistent IPC server. Once started, status/stop/policy changes use authenticated IPC. No system/login service installation or execution grant is implicit. No legacy ticket/JSON-blob fallback. Autoactivation may start the configured same-user daemon but cannot install tools or override an explicit user stop.

## Verification and Change Impact
Planned `VerificationClientTests` **ID-01/04/05, IC-01, IE-04** exercise real sockets, two SDK/MCP clients, lost ACK/restart, incompatible versions, bounded streams, revocation and session close while shared work continues. Recheck Hosting and frontend wrappers on wire changes.

### Concrete authentication and delivery profile
The client verifies the socket server's kernel-reported executable digest before sending credentials. The host admits only policy-approved peer code; descriptive labels do not confer grants. Session credentials bind the actual peer audit identity on every connection. A separately issued resume credential may restore the same durable principal from approved peer code under the current policy; it cannot enlarge its original capability set. The client owns and explicitly preserves that secret when reconnection across processes is needed. A new client without that credential receives a distinct principal.

Envelope preparation and operation acceptance are separate public SDK steps. High-level operations report `OperationDeliveryError` containing the fixed prepared operation when acceptance delivery is uncertain, allowing receipt reconciliation without creating new work. There are no implicit mutating retries. Request/response sizes and simultaneous calls are bounded; shutdown closes owned sockets and finishes local observation without cancelling accepted work.

The production endpoint pins both kernel-reported signed code identity and executable-file digest, then checks the exact expected engine identity in the handshake. A matching on-disk path digest alone does not establish which code an already-running process loaded after a rebuild. Administrative stop after rebuilding uses the separate host-control contract; ordinary session connection does not weaken these checks to connect to a different engine.

AdministrativeSocket is the native administrative-only peer adapter. It compares the kernel UID/audit token/PID/birth identity to the private record established by the original validated server, then transfers its descriptor into LocalConnection for existing bounded framing. It deliberately does not validate the replacement disk image as the old running code. Ordinary LocalVerificationClient still requires its signed code, file digest and engine pins. Executable replacement, PID/birth/audit mutation, unsafe credential files and signal-driven detached shutdown have separate real-process regression coverage.

WatchControlling uses the same fixed prepare/accept protocol as other operations. Per-principal watch queries run on the data channel; read scope cannot stop a watch. Stopped historical records remain queryable by their original ID. The client never implements the monitoring loop.

sourceHead exposes the separately committed source observation without private file bytes. currentView may deliberately retain a historical published view while sourceHead is uncertain or refers to newer source; the immutable view is not rewritten to claim current verification. These independent references are not an overall safety verdict.

### Local client profile
LocalClientProfile owns only private principal-resume storage, outside the workspace and daemon Store. A bounded cross-process file lock serializes first connection and credential publication so concurrent CLI/MCP clients keep one original principal. The record binds workspace, profile name, requested capability ceiling and exact engine. Changed scope/engine fails explicitly; a caller chooses another profile to create independent authority. Unsafe owner/type/mode/symlink files fail before credentials are sent. Profile I/O cannot read source, plan or evidence files. Closing a profile-created client detaches that session only.

### Session renewal
refreshSession performs a same-engine, same-principal resume handshake under the existing capability ceiling. Concurrent renewals share one owned task. Ordinary calls renew locally expired credentials before sending their request, without retrying a mutating RPC. An epoch/authentication error after transmission remains explicit; callers may refresh then reconcile original receipts. Old formal reader handles/cursors retain their original session lifetime and are never transferred. Shutdown closes sockets, drains calls and the owned renewal task, and cannot restore a credential after close.
