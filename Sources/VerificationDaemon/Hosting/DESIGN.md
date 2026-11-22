# VerificationDaemon.Hosting

## Purpose and Scope
**Implementation in progress; behavioral evidence and remaining gates are recorded in PROGRESS.md.** Own the daemon lifecycle, local IPC and workspace composition. Parent: [Daemon](../DESIGN.md). No children.

## Responsibilities and Boundaries
Own one same-user process per canonical workspace, check peer UID and route typed workspace requests to Runtime. Keep control/status responsive. No model semantics, alternate source index or UI execution scheduler.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Daemon](../DESIGN.md) | parent | Composition | Runtime host | Implemented module |
| [Client Session](../../VerificationClient/Session/DESIGN.md) | used by | Protocol major 3 | Public transport | All frontends are clients |
| [Coordination](../../VerificationRuntime/Coordination/DESIGN.md) | depends on | Durable operations/interests | Task authority | Client disconnect is not shutdown |
| [Watching](../../VerificationRuntime/Watching/DESIGN.md) | depends on | Durable monitoring | Workspace lifetime | No CLI watch loop |
| [Publication](../../VerificationExplorer/Publication/DESIGN.md) | depends on | Authorized Provider connection | User GUI | Explorer owns Provider registration |

## Architecture
```text
same-user private socket -> typed workspace requests -> daemon ports
  -> change capture / plan preparation / watch / verification / evidence queries
separate daemon control loop -> status / cancel / drain / recovery
```

## Contracts and Invariants
A pure model-generation plan uses the built-in translator and binds its captured source and configuration. The backend records checker execution and assurance separately.

Proposed `VerificationDaemonServing.serve(DaemonConfiguration) async throws` is composed by `invar daemon serve`. `start/status/stop` are administrative client operations. The same executable may host clients, daemon and private worker modes; no second verifier binary is required. Engine identity explicitly binds coordinator/worker code, schemas, Formal resources and tool policies.

Private socket and lock paths bind the canonical workspace and macOS user. The owner lock prevents duplicate daemons. The transport checks the peer UID before reading requests.

The CLI explicitly starts the workspace daemon and clears its user-stop latch. MCP starts the same workspace daemon on demand while the latch is clear. Explorer connection readiness is recorded separately from runtime recovery.

```text
starting -> recovering -> ready / sourceOffline / approvalRequired
                  └───> recoveryBlocked
ready/offline/approvalRequired -> draining -> stopped
```
The approvalRequired lifecycle state reports Explorer’s Provider registration. Control and history queries remain available during source unavailability; new source-dependent work is explicitly blocked. Startup validates the store format, records the new engine epoch, stops and reaps recorded interrupted processes and reconciles internal and Provider-owned acceptance records before opening admission. The Provider ledger is initialized before registration; external accepted-but-unfinished work follows Coordination’s no-new-start recovery rule. An incompatible daemon protocol or already-running engine requires an explicit stop and restart.

Stop modes are drain or cancel with an explicit policy-bounded deadline. Both close admission and disable watch/action pumps first. Queued never-started requests become explicit cancelled/deferred terminal outcomes per stop mode; running work drains to the deadline then cancellation/reap is awaited. Persist terminal state, finish streams, release source leases/host sessions and close Store last. A failed cleanup reports recoveryBlocked/incomplete stop, not stopped success. Signals enter the same state machine.

## State, Ownership, and Lifecycle
The daemon owns the Store, scheduler, coordinator and source-facing services. One owner lock covers the workspace. Bounded control and data sockets remain distinct.

## Failure, Concurrency, and Constraints
Bound connections, requests, streams, queue reservations, event bytes and control deadlines. Reserve control capacity independently of bulk graph and source data.

## Verification and Change Impact
Planned **ID-01..06** cover exclusive process ownership, two different frontends, watches surviving detach, SIGTERM/SIGKILL recovery, explicit stop latch, unsupported formats/engine replacement, saturated control/data traffic and complete shutdown. Current process recovery tests are reusable for the same supervisor primitives, not proof of the new host.

### Local transport and endpoint identity
The socket directory is private to the workspace owner. LocalConnection verifies the kernel-reported peer UID. The ordinary client pins the server executable identity and checks the reported workspace and engine. Host control uses the original server process identity recorded when it starts.

The lower LocalConnection frame cap is 4 MiB, including one bounded receive-chunk overshoot before rejection. The host accounts that pre-decode buffer and limits concurrent decoders; it applies the smaller typed request cap after decoding. It does not claim a smaller allocation cap than the actual transport provides.

`DaemonEndpointPaths` derives the runtime lock/socket names from the authoritative workspace ID and actual UID, independently of a selected state directory. Changing --state cannot create another owner of the same workspace. `DaemonOwnership` takes a nonblocking exclusive private-file lock before its caller may open Store. State-root validation resolves existing ancestors through OS realpath and rejects paths inside the indexed workspace, including /var aliases and symlink parents. Ownership release is explicit; deinit only closes a still-owned descriptor and never waits for asynchronous shutdown.

### RPC listener ownership
`DaemonRPCServer` implements bounded one-request connections over the actual LocalSocket/LocalConnection transport and kernel-checked peer UID. Separate control/data listeners have independent capacities so bulk reads cannot occupy control slots. With two connections per selected listener, its pre-decode transport buffer allowance is at least two times the lower 4 MiB frame cap plus receive-chunk overhead, independently of the post-decode 64 KiB typed-request cap. Application replies are limited to 1 MiB. Caller policy selects the listener capacities and accounts these buffers.

Rejected/disconnected individual peers do not stop a listener. A nil handler reply deliberately closes without ACK; it is not an application outcome and clients reconcile the fixed receipt. Shutdown closes admission, cancels/drains owned connection tasks, closes the listener and unlinks only the socket inode it created. The composition root retains the workspace lock through this cleanup and Store close.

DaemonRequestDispatcher implements protocol 3. It validates exact request fields, workspace and channel. Preparation fixes the request deadline and fingerprint. Acceptance routes the bound operation to the durable coordinator. Evidence reads return original workspace records.

`DaemonState` owns the actual host lifecycle; status receives the current committed watch count from WatchRepository. Its status is runtime metadata, distinct from immutable verification truth. Phase transitions reject invalid lifecycle edges; a failed recovery/shutdown cannot claim stopped success. Protocol handlers do not call compilation or source capture inline.

### Concrete host composition and administrative control
`WorkspaceDaemon` owns the ownership lock before opening Store, one shared scheduler/coordinator, source-facing services and the two RPC listeners. A `DaemonServicesBuilding` port supplies the workspace operations/source-comparison lifecycle after Store exists; this avoids giving clients persistence or planning ownership. Production uses an Explorer-backed implementation, while host lifecycle tests can use a temporary captured workspace. The factory provides services through the injected port.

The private host-control record binds the active epoch, ordinary endpoint and actual process UID, PID, start time and audit identity. LocalDaemonAdministration validates the record and the kernel-reported peer before sending status or stop. These calls remain usable while source services are offline.

Explicit serve/start clears the user-stop latch; automatic activation must respect it. Explicit stop durably writes the latch before acknowledgement, closes coordinator/service admission, drains to the supplied bounded deadline, then cancels/drains remaining work. Listeners stay available for control status during draining and close before Store. Startup failure/recovery failure closes all acquired resources and releases ownership only after cleanup. Root shutdown is explicit and shared by normal stop, cancellation and listener failure. No idle timer ends residency.

The administrative adapter uses the original kernel audit, PID and start identity so the user can stop the running daemon after its executable has been replaced on disk. Ordinary clients require the pinned code, file and engine identities. Both paths use the existing bounded frame transport.

Compatible-state recovery failure keeps the control and history listeners alive in recoveryBlocked, with new-request admission closed. The host drains any partially recovered tasks before presenting that phase. Administrative stop still performs the same owned cleanup; a blocked host cannot reopen admission by a status read. Unsupported Store schema fails before unsafe state is exposed.

Watch queries use the original workspace ID. Listing returns at most 32 current registrations. Historical watches use exact-ID lookup. Both status paths derive watchCount from retained registration heads.

DaemonManagedServices is the optional lifecycle port for source-facing services needing coordinator ownership. WorkspaceDaemon binds it after coordinator creation and activates monitoring only after recovery and admission opening. Production Explorer services route watch registration/stop to WatchRegistry before the source-operation resource path. Closing services drains monitoring while the coordinator is still available; Store closes last. Lifecycle fixtures without monitoring need not implement this port.

Administrative stop records its request ID before exposing the stop condition. RPC completion notifies the host only after that request's response-write attempt has finished, including transport failure. The host drains these bounded response attempts before shutting listeners; it does not cancel its own stop acknowledgement. Frame writes retain the existing5-second timeout, and a lost response never reverses the durable user-stop latch. Cancellation/listener failure still owns explicit cleanup.

The daemon binds source-facing services to the coordinator before admission opens. Explorer Action delivery uses the original Explorer confirmation and source receipt.

Recovery ordering is physical execution cleanup -> abandoned scratch reservation cleanup -> source activation -> durable demand recovery -> open admission. An old in-process capture/preparation reservation cannot consume capacity after restart, and its transferred committed objects remain intact.
