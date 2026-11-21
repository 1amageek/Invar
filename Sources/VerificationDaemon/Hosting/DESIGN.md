# VerificationDaemon.Hosting

## Purpose and Scope
**Implementation in progress; behavioral evidence and remaining gates are recorded in PROGRESS.md.** Own the daemon lifecycle, principals, IPC and workspace composition. Parent: [Daemon](../DESIGN.md). No children.

## Responsibilities and Boundaries
Own one same-user process per canonical workspace, authenticate clients and route typed authorized requests to Runtime. Keep control/status responsive. No model semantics, alternate source index or UI execution scheduler.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Daemon](../DESIGN.md) | parent | Composition | Runtime host | Implemented module |
| [Client Session](../../VerificationClient/Session/DESIGN.md) | used by | Protocol major 2 | Public transport | All frontends are clients |
| [Coordination](../../VerificationRuntime/Coordination/DESIGN.md) | depends on | Durable operations/interests | Task authority | Client disconnect is not shutdown |
| [Watching](../../VerificationRuntime/Watching/DESIGN.md) | depends on | Durable monitoring | Workspace lifetime | No CLI watch loop |
| [Publication](../../VerificationExplorer/Publication/DESIGN.md) | depends on | Authorized Provider connection | User GUI | Host approval is not a native execution grant |

## Architecture
```text
OS peer + client credential/policy -> authenticated session -> narrow API ports
  -> change capture / plan preparation / watch / verification / evidence queries
separate daemon control loop -> status / cancel / drain / recovery
```

## Contracts and Invariants
A pure model-generation plan uses the existing host verification grant and only the built-in translator. The exact contract approval remains mandatory for every plan containing a configurable checker.

Proposed `VerificationDaemonServing.serve(DaemonConfiguration) async throws` is composed by `invar daemon serve`. `start/status/stop` are administrative client operations. The same executable may host clients, daemon and private worker modes; no second verifier binary is required. Engine identity explicitly binds coordinator/worker code, schemas, Formal resources and tool policies.

Private socket/lock roots use canonical workspace plus OS user identity. An exclusive lock and actual peer identity protect ownership; JSON workspace/PID/name strings alone are not authentication. Daemon issues scoped client credentials after a trusted host policy grants access. Agent labels are descriptive. Read, source/value access, planning, execution and administration are distinct; a payload Bool cannot grant native/Lean execution. Current conversation authorization is not inferred from source comments or logs.

The CLI explicitly starts a workspace daemon. An MCP client may activate an existing configuration with a persisted policy if the user-stop latch is absent. Activation grants no new permissions. Once started, the daemon remains resident until explicit stop or process shutdown. CLI/MCP connection close cannot end watches, Provider registration or other clients' jobs.

```text
starting -> recovering -> ready / sourceOffline / approvalRequired
                  └───> recoveryBlocked
ready/offline/approvalRequired -> draining -> stopped
```
Control/history queries remain available during source unavailability; new source-dependent work is explicitly blocked. Startup verifies stored format/engine/policy, stops/reaps recorded interrupted processes and reconciles internal and Provider-owned acceptance records before opening admission. The Provider ledger is initialized before registration; external accepted-but-unfinished work follows Coordination’s no-new-start recovery rule. Format/engine mismatch is an explicit restart/new-state requirement, never a compatibility fallback.

Stop modes are drain or cancel with an explicit policy-bounded deadline. Both close admission and disable watch/action pumps first. Queued never-started requests become explicit cancelled/deferred terminal outcomes per stop mode; running work drains to the deadline then cancellation/reap is awaited. Persist terminal state, finish streams, release source leases/host sessions and close Store last. A failed cleanup reports recoveryBlocked/incomplete stop, not stopped success. Signals enter the same state machine.

## State, Ownership, and Lifecycle
DaemonRoot owns Store, Scheduler, WatchRegistry, ProviderConnection, policies and worker supervisor. Session authority and bounded connection tasks are actor-owned. All nontrivial preparation/compilation/inventory/graph extraction is queued worker work, not inline IPC-handler CPU. No async cleanup is delegated to deinit.

## Failure, Concurrency, and Constraints
Bound connections, principals, requests, streams, queue reservations, event bytes and control deadlines. Reserve control-plane capacity independently of bulk graph/source data. Persist administrative policy revisions and revoke outstanding authority before new work. Credentials never appear in contributions or exported views.

## Verification and Change Impact
Planned **ID-01..06** cover exclusive process ownership, two different frontends, watches surviving detach, SIGTERM/SIGKILL recovery, explicit stop latch, revoked policies, unsupported formats/engine replacement, saturated control/data traffic and complete shutdown. Current process recovery tests are reusable for the same supervisor primitives, not proof of the new host.

### Concrete principal and peer profile
Host policy separately lists approved executable digests/capabilities and exact approved configuration/oracle/harness/corpus entries. The server constructs principals from actual same-user kernel peer identity and random host-issued credentials. A label, PID or client capability request alone grants nothing. Each live credential is bound to that process's audit identity. An optional resume secret, retained only as a digest by the host, preserves the durable principal across approved process reconnection while restricting it to its original grants intersected with current policy. A policy revision change invalidates live credentials before new admission. Administrative control uses a separate private host credential and is not exposed as an MCP tool.

The lower LocalConnection frame cap is 4 MiB, including one bounded receive-chunk overshoot before rejection. The host accounts that preauthentication buffer and limits concurrent decoders; it applies the smaller typed request cap after decoding. It does not claim a smaller allocation cap than the actual transport provides.

`DaemonEndpointPaths` derives the runtime lock/socket names from the authoritative workspace ID and actual UID, independently of a selected state directory. Changing --state cannot create another owner of the same workspace. `DaemonOwnership` takes a nonblocking exclusive private-file lock before its caller may open Store. State-root validation resolves existing ancestors through OS realpath and rejects paths inside the indexed workspace, including /var aliases and symlink parents. Ownership release is explicit; deinit only closes a still-owned descriptor and never waits for asynchronous shutdown.

### RPC listener ownership
`DaemonRPCServer` implements bounded one-request connections over the actual LocalSocket/LocalConnection transport and actual ConnectionPeer identity. Separate control/data listeners have independent capacities so bulk reads cannot occupy control slots. With two connections per selected listener, its preauthentication transport buffer allowance is at least two times the lower 4 MiB frame cap plus receive-chunk overhead, independently of the post-decode 64 KiB typed-request cap. Application replies are limited to 1 MiB. Caller policy selects the listener capacities and accounts these buffers.

Rejected/disconnected individual peers do not stop a listener. A nil handler reply deliberately closes without ACK; it is not an application outcome and clients reconcile the fixed receipt. Shutdown closes admission, cancels/drains owned connection tasks, closes the listener and unlinks only the socket inode it created. The composition root retains the workspace lock through this cleanup and Store close.

`DaemonRequestDispatcher` is the concrete authenticated protocol-2 handler. It checks exact envelope fields and typed round-trip decoding, authenticates the kernel peer/session, fixes the original scoped request deadline, and routes acceptance to the durable coordinator. Caller-provided capability/approval Booleans have no authority. Source/log/value-bearing immutable records require sourceValues; read/status/receipt/current-view references remain separate. These protected records are returned unchanged rather than redacted and falsely assigned their original content identity. A bounded public committed-view projection remains the publication owner's responsibility.

`DaemonState` owns the actual host lifecycle; status receives the current committed watch count from WatchRepository. Its status is runtime metadata, distinct from immutable verification truth. Phase transitions reject invalid lifecycle edges; a failed recovery/shutdown cannot claim stopped success. Protocol handlers do not call compilation or source capture inline.

### Concrete host composition and administrative control
`WorkspaceDaemon` owns the ownership lock before opening Store, one authenticated authority, one shared scheduler/coordinator, source-facing services and the two RPC listeners. A `DaemonServicesBuilding` port supplies the workspace operations/source-comparison lifecycle after Store exists; this avoids giving clients persistence or planning ownership. Production uses an Explorer-backed implementation, while host lifecycle tests can use a temporary captured workspace. The factory does not authorize peers or execution.

A private host-control record stores the current epoch, actual server code/process-start identity, pinned ordinary endpoint and a separate random administrative secret. `LocalDaemonAdministration` validates ownership/type/mode and actual socket peer UID/audit-token/PID/start identity before sending this secret. Ordinary sessions never obtain administration. Administrative status/stop/policy-apply remain available while source services are offline or policy is missing. A running executable replacement does not weaken the normal endpoint pins; stop uses the original kernel audit/process/start identity rather than accepting the new file digest as the old engine.

Explicit serve/start clears the user-stop latch; automatic activation must respect it. Explicit stop durably writes the latch before acknowledgement, closes coordinator/service admission, drains to the supplied bounded deadline, then cancels/drains remaining work. Listeners stay available for control status during draining and close before Store. Startup failure/recovery failure closes all acquired resources and releases ownership only after cleanup. Root shutdown is explicit and shared by normal stop, cancellation and listener failure. No idle timer ends residency.

Actual atomic executable replacement makes the common transport SecCodeCheckValidity fail against the changed disk image. The administrative adapter therefore authenticates the already established process using the exact kernel audit token, same UID, PID and start time recorded when the original code was validated. It then uses the common LocalConnection framing without calling its disk-dependent peerIdentity. This narrower route accepts only private host control, never ordinary session/verification calls. Normal Client code/file/engine pins are unchanged. A new PID, audit token, birth identity or private secret rejects before sending administrative authority. The adapter uses only scoped native socket buffers/descriptors; it introduces no second frame protocol.

Compatible-state recovery failure keeps the already authenticated control/history listeners alive in recoveryBlocked, with new-request admission closed. The host drains any partially recovered tasks before presenting that phase. Administrative stop still performs the same owned cleanup; a blocked host cannot reopen admission by a status/policy change. Unsupported Store schema/engine fails before unsafe state is exposed.

Watch queries enforce exact workspace/principal ownership. Listing returns at most32 current registrations; historical stopped/expired records use exact-ID lookup. Both authenticated and administrative status derive watchCount from retained registration heads so a registration commit is visible without waiting for an in-memory pump.

DaemonManagedServices is the optional lifecycle port for source-facing services needing coordinator ownership. WorkspaceDaemon binds it after coordinator creation and activates monitoring only after recovery and admission opening. Production Explorer services route watch registration/stop to WatchRegistry before the source-operation resource path. Closing services drains monitoring while the coordinator is still available; Store closes last. Lifecycle fixtures without monitoring need not implement this port.

Administrative stop records its authenticated request ID before exposing the stop condition. RPC completion notifies the host only after that request's response-write attempt has finished, including transport failure. The host drains these bounded response attempts before shutting listeners; it does not cancel its own stop acknowledgement. Frame writes retain the existing5-second timeout, and a lost response never reverses the durable user-stop latch. Cancellation/listener failure still owns explicit cleanup.

Managed services bind the actual DaemonAuthenticating owner with the Coordinator before activation. Provider Action preflight opens a real session for ConnectionPeer.current under existing host peer policy; it receives no implicit execution authority from Explorer. The optional ExternalAdmissionAuthorizing service consumes only live SDK permits; it is not exposed over IPC.

Recovery ordering is physical execution cleanup -> abandoned scratch reservation cleanup -> source activation -> durable demand recovery -> open admission. An old in-process capture/preparation reservation cannot consume capacity after restart, and its transferred committed objects remain intact.
