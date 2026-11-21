# VerificationRuntime.Coordination

## Purpose and Scope
Own one daemon's durable workspace operations, execution interests and request reconciliation. Parent: [Runtime](../DESIGN.md). No children. **Target schema-2 contract supersedes the current ticket/whole-plan-tail coordinator.**

## Responsibilities and Boundaries
Coordinate changes, preparations, watches and run demands through injected Core Store/planning/execution ports. No source index or backend semantics. Hosting authenticates requests; Store owns transactional acceptance; Scheduling owns resource admission.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Runtime](../DESIGN.md) | parent | Workspace ownership | Composition | One per workspace/user |
| [Changes](../../VerificationCore/Changes/DESIGN.md) | depends on | Change transitions | Agent claims | No author inference |
| [Evidence](../../VerificationCore/Evidence/DESIGN.md) | depends on | Run demands/associations | Shared work | Demand differs from execution |
| [Scheduling](../Scheduling/DESIGN.md) | depends on | Job keys and reservations | Concurrent work | No unbounded tail of whole runs |
| [Store](../../VerificationStore/Persistence/DESIGN.md) | depends on | Atomic receipt + operation creation | Durable authority | No dual writable ledgers |

## Architecture
```text
internal validated request -> atomic receipt + operation/run demand
external Provider request -> SDK reserve -> Store receipt mapping + operation
  -> capture / preparation / job references -> shared scheduler
  -> immutable evidence + associations -> one committed view revision
observers -> subscriptions; watches/run demands -> execution interests
```

## Contracts and Invariants
Acceptance commits `(principal scope, request key, fingerprint, receipt, operation id)` and its operation row in one Store transaction before work starts for internal SDK requests. Same key/fingerprint returns the same initial receipt; changed content conflicts. Deadline, retention, authenticated request-envelope identity and revoked authority are checked independently of entry presence. A new authorization epoch cannot admit an old unrecorded envelope; historical lookup never creates work. Missing durable state after uncertain delivery is outcomeUnknown, never permission to create replacement work.

### Explorer Provider acceptance boundary
The current owner [Provider SDK](https://github.com/1amageek/ArchitectureExplorer/blob/main/Sources/ArchitectureClient/ExtensionProvider/DESIGN.md) requires its concrete `ProviderActionLedger.reserve`; only the live `mayStart=true` result permits starting work. Use that SDK, rather than replacing it with a nominally equivalent SQLite implementation. Initialize its workspace-private ledger before Provider registration/action delivery and charge it to Store policy.

After reservation, Store atomically creates the exact receipt-to-demand mapping and operation using the SDK receipt.jobID. No execution starts until both writes succeed. The live coordinator retains the first-start permit; duplicates and reconciliation use `lookup` and cannot mint another permit. These two persistence owners are **not one transaction**. A Store failure after SDK acceptance leaves the initial accepted receipt unchanged and reports failed/unknown execution, never a replacement receipt or fabricated completed demand.

After restart, reconcile the SDK receipt with the Store record and process journal. An external request without durable completion cannot acquire a new start permit, including a queued request that never began; mark it interrupted/not-started or outcomeUnknown according to actual records. A missing mapping can create a historical recovery record with the same job id, never runnable work. Started executions are stopped/reaped under the existing supervisor contract. The user may submit a separately confirmed fresh request; recovery never does so automatically. Internal CLI/MCP requests use the single-Store transaction above and can resume proven never-started demand under current authority. This deliberately preserves the lower SDK's safety contract at the cost of automatic external-demand resumption after a crash.

Accepted work and observer interests are separate. An Agent may cancel its own run demand; shared underlying executions remain while another run/watch needs them. AEX receipt.jobID identifies the admitted demand, not the shared worker execution. A cancelled demand reports release/cleanup of that demand plus any continued shared execution for other consumers. Workspace-wide execution cancellation is a separate administrative authority. Cancel acceptance means cancelling; terminal cancelled follows actual owned cleanup. Concurrent normal completion wins if already committed.

Restart reconstructs internal accepted never-started demand under current authority, verifies recorded process identities, stops/reaps interrupted owned executions, and marks uncertain started work interrupted. It does not restart started native/proof work from lost delivery. New session ids/credentials do not change logical operation ids. Reconnect reconciles receipts/status without implicit execution.

## State, Ownership, and Lifecycle
Actor state contains ids/revisions/reservations, not whole queued plans. Store is the durable source of truth. Observers have bounded subscriptions; watches and accepted run demands retain independent interests and pins. Stop disables new admission and watch/action pumps, drains/cancels owned operations, awaits process cleanup, closes streams and Store. No deinit wait. Actor decisions are rechecked after persistence suspension.

## Failure, Concurrency, and Constraints
All capacities come from persisted workspace policy and negotiated endpoint caps. Admission counts in-flight reservations as well as committed entries. Terminal unobserved memory entries are released immediately; retained records remain bounded by Store policy. Whole-run/attempt/tool/cleanup deadlines are distinct. Receipt persistence failure cannot expose accepted/completed success.

## Verification and Change Impact
Planned **ID-01..06** test actual daemon/socket concurrency, lost ACKs, duplicate/conflicting requests, detach versus cancellation, durable watches, restart/no duplicate execution, full queues, revocation and shutdown. Retain relevant current CoordinatorTests until new cases cover the replacement; delete obsolete ticket-resubmission tests at cutover.

### Concrete durable operation coordinator
`WorkspaceCoordinator` consumes a daemon-issued fixed envelope plus typed operation. It checks the canonical fingerprint and injected current host authority, atomically records the original receipt and queued demand, then starts only that retained demand. Separate idempotency keys create separate interests even when their jobs share an execution. Duplicate delivery reconciles the same operation ID. The coordinator owns no observer tickets and no plan tail. A bounded map contains operation IDs and tasks; Store remains the history owner.

Acceptance captures the source-head revision. Verification uses the shared scheduler without independently committing the run. Terminal demand, immutable run and source-fenced common view commit together. Cancel first persists `cancelling`, then releases that demand's interests and awaits its cleanup; other demands remain live. Restart never resumes a running or external request. Internal queued requests may resume only after unchanged typed input, original deadline and current policy are revalidated. Persistence/cleanup failure is surfaced as recoveryBlocked rather than successful completion.

The host constructs WorkspaceCoordinator with new-request admission initially closed. Recovery and source/session initialization complete before openAdmission; separate control/history IPC is available while recovering. closeAdmission is one-way for a stopping instance. A stop received during recovery terminalizes never-started queued requests instead of starting them. Existing recovery permits never bypass a stopped coordinator.

### Publication ordering
WorkspaceCoordinator optionally receives VerificationPublishing; production Explorer services supply it. reserve completes before scheduler.run. On result completion, prepare creates the exact immutable delivery record for that view; completeDemand atomically commits it. Publisher transport failures are represented in the outbox and do not change the run verdict. A reserved attempt without a committed view after restart is blocked as interrupted and never starts result work.

Cancellation and terminal failure use Store-owned atomic read/transition operations. They preserve execution interests attached concurrently; a stale coordinator revision cannot turn normal cancellation into a persistence failure. Cancellation requests recheck the durable principal inside the transaction. Failure completion derives cancelled versus failed from the current durable state after cleanup.

WorkspaceCoordinator.submitWatch uses the narrow Store-issued watch envelope, then the same admission/scheduler path. Every fixed watch envelope supplies a capability ceiling even without a live session. Recovery rechecks current registration authority/stage before resuming accepted queued watch work; it does not renew the initial deadline.

The reconcile operation reserves publication before reassessment, uses Core EvidenceReconciliation, and atomically commits a view result with no new run/execution. It uses the fresh input source fence and preserves original evidence. Store repeats the semantic validation in the transaction; a different scope cannot become current through this operation.

Source-fence admission compares sourceIdentity, allowing different contract closures under one authoritative source snapshot. Reassociation still requires full capturedScopeDigest equality; this source comparison cannot authorize evidence reuse by itself. Result completion appends assessment history, while publication acknowledgement alone selects the default view.

External admission accepts only a consumed live ExternalAdmissionAuthorizing permit. ProviderActionRepository atomically maps its SDK job ID to one queued provider-origin demand and receipt; both original envelope and authority are checked. External queued/running demands never resume during recovery. The ProviderActions daemon component owns receipt reconciliation and nonrunnable acceptance gaps.

ExternalWorkspaceCoordinating refines the ordinary request interface for the internal Provider composition. Ordinary coordinators do not acquire a default unsupported external API; the production WorkspaceCoordinator implements both contracts.

A node-scoped verification request carries a snapshot and entity together. Admission requires a matching plan snapshot and a member of its immutable entity inventory. The selected entity is the context for the report; the approved job names the source under verification.
