# VerificationRuntime.Watching

## Purpose and Scope
**Daemon monitoring implementation in progress; acceptance evidence is recorded in PROGRESS.md.** Own daemon-held authorized change subscriptions and re-verification demand. Parent: [Runtime](../DESIGN.md). No children.

## Responsibilities and Boundaries
Observe source/context/oracle/capability invalidations, mark associations uncertain immediately, acquire coherent replacements and request bounded plans. No source index, independent queue or view verdict calculation.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Runtime](../DESIGN.md) | parent | One workspace owner | Watch lifetime | Independent of CLI/MCP lifetime |
| [Coordination](../Coordination/DESIGN.md) | depends on | Durable watch/run interests | Shared admission | No duplicate task per frontend |
| [Changes](../../VerificationDiscovery/Changes/DESIGN.md) | depends on | Conservative delta/impact | Replan scope | Unknown closure disables reuse |
| [Connection](../../VerificationExplorer/Connection/DESIGN.md) | depends on | Authorized events/capture | Source authority | Separate source epoch/sequence |

## Architecture
```text
persisted WatchRegistration + policy -> input events
  -> append uncertain association -> bounded settle/capture
  -> sealed change/input -> impact -> shared plan/job demand
```

## Contracts and Invariants
A registration pins workspace/scope, contract/policy revision, methods, budgets, execution permissions, expiration if any and enabled state. Agent disconnection does not disable it. Explicit disable/revoke stops its monitoring and releases its execution interest after cleanup. Restart rechecks policy/tool identities and reestablishes source subscriptions; it never assumes an old live session or restarts an execution whose start outcome is unknown.

Filter AEX origin/category so own annotations/publications are not source invalidations. Epoch gaps and unknown events force resync and unknown applicability. Actual original bytes/context/contract/tool closure determine reuse, never snapshot generation alone. Tool/policy/oracle changes are observed as explicit inputs even without a source event. A reconnect may confirm identical inputs and retain evidence via a new association, without re-executing.

Continuous edits coalesce capture/replan demand under policy settle/time budgets, without postponing the uncertainty marker. Older runs may finish historically. Starvation is visible; an explicitly selected fixed snapshot can be verified independently of current edits. Policy revocation prevents fresh execution, including restart activation.

## State, Ownership, and Lifecycle
WatchRegistry actor owns registrations, event cursors and coalesced demand references; no full source arrays in queues. One source subscription per workspace is shared. Shutdown finishes progress streams and drains capture/tasks. The old CLI Watching component is removed at replacement, not wrapped.

## Failure, Concurrency, and Constraints
Bound watches, pending capture generations, settle delay, event queue, read budgets and retry backoff. Keep control/status reads responsive; heavy hash/compile/inspection runs in workers. Source daemon unavailability yields visible unknown/offline, not a second index or host fallback.

## Verification and Change Impact
Planned **ID-02/03, IC-04, IE-02** cover Agent exit, restart, source edits/reconnect, policy/tool changes, own-publication loops, continuous edits and a manual fixed-snapshot run. Current watch E2E proves only the legacy CLI loop; it is not acceptance of this owner transfer.

### Concrete daemon cutover plan
The CLI-owned WatchCommand, preparation helpers and idle WorkspaceService are removed. WatchRegistry owns the actual runtime workflow; CLI/MCP submit and observe the same durable daemon registration.

WatchRecord will retain its original principal, policy revision, capability ceiling, configuration path, run budget and principal expiration independently of the initial session. Its scalar cycle state owns generation, pending preparation/verification demand IDs, last sealed plan/run/view references and diagnostics. Active plus paused registrations are bounded; stopped/expired registrations do not admit new interests. Current policy/expiry is rechecked on recovery and every derived demand. A policy revision change pauses the original watch rather than extending its grants.

Derived watch envelopes require a narrow Store operation bound to an existing registration; ordinary agent envelope issuance still requires its live authenticated session. The coordinator keeps the original watch ceiling when rechecking authority. Deterministic watch-generation/stage keys preserve acceptance after an uncertain response. Source continuity loss invalidates the common source fence before any coalesced preparation. One SourceEventReading cursor belongs to the workspace, not to each client/watch.

Identical captured scope may create a new evidence association/view after exact source/context/configuration/tool/profile comparison; it must retain original evidence identity and upstream unknown boundaries. This comparison is distinct from shared-job cache eligibility. No display-name/snapshot-generation comparison permits reuse. A changed fixed scope creates a fresh durable verification demand after current exact-contract approval; the existing scheduler owns all workers and cancellation cleanup.

### Registration and stop lifecycle component path
Internal WatchLifecycle owns staging a registration from its original running authenticated demand and beginning/finalizing a durable stop. It does not promise source monitoring by itself. Coordinator terminal commit activates the staged record. The future WatchRegistry drains its in-memory probe/cycle tasks between beginStop and finishStop; finishStop also cancels/drains every existing deterministic current-cycle child, even if the receipt was accepted before its pending pointer was attached. A missing recorded child is integrity failure; an absent deterministic child without its original receipt proves no acceptance. No replacement key/demand is minted during cleanup.

Lifecycle shutdown closes new registration and awaits owned stop finalizers; it does not disable committed durable registrations merely because an Agent/daemon invocation detaches. Monitoring/cycle ownership remains the registry's separate contract. WatchLifecycleTests own staged registration, foreign-principal refusal, explicit stop and the real Task cancellation/receipt-gap path; these are not yet production source-monitor acceptance.

The registry/daemon closes external control admission and drains accepted registration/stop calls before WatchLifecycle.shutdown. That lower shutdown rejects fresh control scopes and awaits its already owned finalizer tasks. A registration admitted before close may finish under its original deadline; explicit task cancellation still aborts its staged record through Coordinator.

### Single-cycle execution owner
Internal WatchCycleDriver owns one in-flight cycle per watch and uses only WatchRepository authority, WatchInputProbing and WorkspaceCoordinating contracts. It persists a generation/stage before accepting a deterministic preparation/verification/reassociation child. An existing child is resumed by its original demand ID; a missing child with a receipt is integrity failure. It never generates a replacement key after uncertain acceptance. The preparation child's exact retained result chooses the next stage. Identical complete captured scope may reassociate prior completed evidence; other scopes execute through the shared coordinator. Terminal metadata uses RunDemand.view, independently of global current-view selection. A quiet probe does not create a new cycle or revision.

Task cancellation drains this watch's deterministic children through WatchLifecycle before returning. Stop/pause races cannot reopen an active stage: each metadata write rechecks active state, generation and expected revision. Noncancellation failure drains children before recording an idle diagnostic; retry policy belongs to the registry, not a busy retry loop here. This internal driver does not own the source event pump, registration activation or global view/publication selection. Component tests use real Store/Coordinator/static backend with an injected preparation/probe fixture and certify only this boundary.

### Workspace registry composition
WatchRegistry owns one independent metadata source-event pump, one bounded cycle-admission pump and at most WatchPolicy.maximumConcurrentCycles driver tasks. The event pump persists uncertainty before coalescing replacement work; it never waits for compilation/worker cleanup. The cycle pump rechecks fixed authority/expiry even while source is unavailable, pauses revoked watches before draining their interests and completes persisted stopping records on startup. Quiet probes do not create revisions. Initial activation/reconnect forces a coherent capture; unchanged complete scopes reassociate rather than rerun. A failed prepared execution retains its prepared baseline so a quiet timer cannot repeatedly restart uncertain/failed work; a new source/tool/configuration observation is required.

WatchPolicy owns configurable operational intervals and cycle concurrency. Development defaults poll0.5s, probe3s, failed-preparation retry5s, settle0.25s with a maximum1s coalescing delay and two concurrent cycles. Finite positive bounds and maximum32 cycles are validated; deployment may select values within those bounds. These are scheduling controls, not proof claims or substitutes for shared ResourcePool admission. One scalar source version coalesces events, with scalar per-watch observed versions/probe deadlines; no unbounded event queue or source payloads are retained.

The daemon binds the registry after constructing its coordinator, initializes source/recovery while monitoring is closed, then activates pumps only after coordinator recovery/openAdmission. Close stops pumps and cancels/drains driver interests before coordinator teardown. Shutdown retains committed registrations for the next daemon epoch, rather than disabling watches because a process/Agent exits. Accepted registration/stop requests remain coordinator-owned; lower lifecycle shutdown follows their drain. Any cleanup/persistence failure remains explicit.

Pause cleanup uses the atomic Store finishWatchPause transition after draining children. Stop can win during cleanup without a stale revision becoming a global registry failure; no paused cycle is reset while an owned child remains live.
