# VerificationStore.Persistence

## Purpose and Scope
Own the daemon's private immutable evidence store and transactional operation ledger. Parent: [Store](../DESIGN.md). No children. Store schema2 is implemented and the daemon is the sole live writer.

## Responsibilities and Boundaries
Persist changes, inputs, obligations/plans, request receipts/run demands, executions/evidence/associations, watches, common view revisions and publication outbox. No access to Explorer SQLite and no reinterpretation of proof results.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Store](../DESIGN.md) | parent | Persistence boundary | Single writer | No client database handles |
| [Changes](../../VerificationCore/Changes/DESIGN.md) | depends on | Immutable change records | Baseline pins | Dirty/user edits remain facts |
| [Evidence](../../VerificationCore/Evidence/DESIGN.md) | depends on | Evidence/association/view semantics | Shared Agent/UI data | Current association cannot rewrite evidence |
| [Coordination](../../VerificationRuntime/Coordination/DESIGN.md) | used by | Atomic acceptance/transitions | Execution authority | Commit before visible receipt |
| [Publication](../../VerificationExplorer/Publication/DESIGN.md) | used by | Persisted outbox and projection revisions | External delivery | No cross-daemon atomic-commit fiction |

## Architecture
```text
single daemon Store actor -> SQLite transactions + quota/reservation ledger
                         -> private immutable blobs/indexed Formal bundles
committed read revision -> common view -> bounded client query / publication outbox
```

## Contracts and Invariants
Typed ports replace the generic namespace/payload repository interface: `ChangeRepository`, `ExecutionLedger`, `EvidenceRepository`, `WatchRepository`, `PolicyRepository`, `PublicationOutbox` and `RetentionManaging`. Internal SDK acceptance/receipt and operation creation are one transaction. External Provider acceptance is first owned by the SDK ledger; [Coordination](../../VerificationRuntime/Coordination/DESIGN.md) owns its separate fail-closed reconciliation boundary. Store commits its receipt mapping and operation together, without claiming atomicity with the SDK file. Terminal execution, evidence references, demand associations and view revision commit atomically. Optimistic expected revisions guard reentrant async decisions.

Large input/formal/source/log data is in sealed content-addressed files/indexes, not inline plan/report Data. Blob publication precedes reference commit and is fsynced/atomic. Hash/schema/reference checks apply on reads and writes. Concurrent identical immutable writes converge; conflicting bytes fail. No published reference can point at unfinished/missing content.

### Quota, pins and pruning
A persisted StorePolicy owns total logical retained bytes, DB/WAL overhead reserve, file/record counts, staging/scratch reservations, graph-index/page budgets, retention age/count rules and failure/recovery headroom. Defaults are selected from the host resource budget, available resources and measured supported profiles; no new guessed constants are fixed by this design.

Reserve worst-case admitted output and failure headroom transactionally before work; charge actual sealed storage and release unused reservation after cleanup. Refuse infeasible admission. Record logical reservations separately from observed physical disk use; outside filesystem activity can still cause I/O failure, which must remain explicit. DB/WAL/checkpoint and recovery costs are part of the budget, not omitted metadata.

Pins include active input leases/readers, open changes, watches/baselines, queued/running/replay demands, unresolved retained findings, graph queries and unacknowledged publication data and external receipt mappings/ledger retention. Prune only unpinned objects allowed by policy; deletion is recoverable and reference-checked. If pinned data occupies the quota, reject/defer new demand rather than evict active evidence. Retained tombstones preserve deleted subjects and request reconciliation until policy retention ends. Internal request envelopes are daemon-issued and bind identity/deadline/epoch; after tombstone pruning an expired envelope still fails independent expiry checks and cannot become a fresh request. Reauthorization creates a different envelope identity, never extends an old one. External request expiry is owned by the actual Provider ledger.

### Format replacement
Reject schema-1 live stores and IPC/report formats. Do not migrate, merge or silently reinterpret them. Use an explicitly selected fresh state root; old private data is archived/deleted only by an explicit administrative operation. New runtime has no compatibility reader. Existing developer fixtures do not justify discarding user data automatically.

## State, Ownership, and Lifecycle
One daemon owns the writer lock/SQLite handle; all clients use the SDK. Bounded readers pin a committed revision and blobs. Recovery verifies journals/processes, resolves incomplete file publication and reconstructs only known durable operations. Shutdown rejects writes, drains readers/outbox/capture operations, checkpoints within budget and closes. No synchronous deinit wait.

## Failure, Concurrency, and Constraints
Failures distinguish incompatible format, corrupt/missing content, immutable conflict, revision conflict, quota/resource, revoked access and persistence failure. Roll back the transaction on failure; never acknowledge success before durable commit. Failure-record reserve is owned and monitored; inability to persist is reported, not concealed.

## Verification and Change Impact
Planned **IS-01..05** kill processes before/after each commit boundary, race receipt and job creation, corrupt references, saturate DB/WAL/scratch/reservations, pin during pruning, expire request tombstones and restart interrupted deletion/publication. Reuse current immutable-write/corruption tests where premises remain valid; replace schema-1-specific expectations at cutover.

Worker location lookup validates retained small input references and private directory identity without materializing the whole catalog. Publication binds the plan to the complete captured manifest once; load validates the immutable plan hash and retained references. Each worker independently verifies all bytes it actually consumes (or the static graph reference). Explicit `inputRoot` remains the full capture audit API. Retention links keep plans, descriptors, original inputs, physical executions and evidence reachable throughout their owners' lifetimes.

### Publication charge transfer
When verified output moves from an active reserved scratch root into a new immutable input/artifact/preparation root, Store records an immutable reservation transfer in the publication boundary. Capacity accounting includes both the remaining scratch and its transferred roots, so moving bytes does not recreate unused reservation capacity. Active transfers pin their published objects through retention. Reusing pre-existing published content does not claim it as newly owned capacity. Releasing a reservation removes its transfer links only after the execution/capture owner has completed cleanup and reference publication.

Input capture publication obtains an exact disk reservation from its already bounded file/manifest sizes before writing staging bytes. The staging root is reservation-owned; the publication transaction transfers that charge to the immutable input root. Concurrent identical publication can converge on an already audited root. Store shutdown rejects new captures, cancels pending scans and waits for admitted input-write cleanup before checkpoint/close. Failure cannot leave an accepted over-quota input or an unreleased write reservation.

Capacity admission also reserves the unallocated remainder of the full three-file database/WAL/SHM ceiling. `StoreUsage.reservedBytes` reports active scratch/publication remainder, while `databaseReservedBytes` reports that separate database reserve. Observed database bytes are subtracted exactly once from the reserved ceiling; retaining empty database headroom cannot be mistaken for free worker output space. The original input catalog lives once in its sealed file; SQLite stores its small VerificationInput reference.

Full plan publication atomically publishes its content-bound SchedulingPlan, per-job JobReference indexes and descriptors. Read-side admission/auth/assessment uses small checked metadata; it does not decode the full plan for every queue entry. Job references bind the exact descriptor digest and complete-scoped execution key computed at publication. Descriptor loading remains independently checked after admission. Demand/execution interest attachment validates the target plan/job and either exact descriptor identity or equal complete scoped key, then advances the running demand revision atomically before worker launch.

Quota-neutral reopen checks compare the already persisted policy without inserting it again. Releasing owned reservations is cleanup and uses failure headroom, since a failed terminal row can leave page/record counts above the ordinary admission ceiling. Cleanup must remain possible after a correctly recorded publication failure.

Change records preserve their originating request and baseline. capture(reference) reads only sealed Store bytes and rechecks sizes and digests.

Retention pin publication validates that its object/visible head exists inside the pin transaction. A reader pins its originating evidence, retaining the full input/artifact dependency closure; concurrent pruning cannot create an admitted reader with a missing evidence binding.

### Atomic publication outbox
Publication revisions share the records/heads/link transaction owner. completeDemand includes the ready/blocked delivery record and its exact view in the same transaction as terminal run/evidence. Failed validation rolls all of them back. Active records retain their input and committed view closure. Terminal records remain historical under normal retention. The active inventory returns at most 32 scalar IDs; delivery loads only one resource-admitted payload at a time; individual payloads <=2 MiB, handles <=16 KiB. No SDK credentials or private source bytes belong in an outbox payload.

Source invalidation is a single transaction: advance the uncertain source fence and publish unknown associations for retained evidence before any replacement capture. Later completion must match both fence and confirmation; a late known verdict cannot erase the uncertainty marker. Behavioral owner: StoreLedgerTests.

Watch persistence implements the [Core watch contract](../../VerificationCore/Evidence/DESIGN.md). Registration binds the original accepted demand, workspace, configuration and budget. Updates preserve that binding and use an expected revision.

Verification and reassociation stage issuance check the completed preparation for the current cycle. Quiet probes append no watch records.

### Published selection
commitView owns immutable assessment history only. savePublication(committed) requires a complete envelope and original provider slot/generation, then updates PublishedViewHead in the same transaction if newer. The pointer retains its publication and exact view closure. It is independent of source fences/history sequence and survives reopen; unconfirmed/partial/failed/superseded work cannot select it. latestView returns this confirmed published reference or nil. Internal latestAssessment reads the separate history head for conservative invalidation composition.

Confirmed observeInput deduplicates by the compact sourceIdentity/epoch rather than full verification input identity. Multiple configurations of the same authenticated source snapshot cannot invalidate one another. Uncertain-to-confirmed observation still creates a fresh revision.

Watch stop/pause entry points own atomic read-and-transition, preserving the latest cycle/pending references. Runtime drains those exact children after admission closure; it does not derive a replacement revision from a stale earlier snapshot.

Provider Action preflight is immutable and size-bounded; scalar revisions retain its original authority/run. Atomic acceptExternalDemand requires that retained mapping and original fixed envelope, records the concrete SDK job ID, receipt and queued demand together. Recovered gaps are outcomeUnknown and never admitted. Store never grants a first-start permit; only the concrete SDK owner does.

Startup reservation recovery runs after physical worker/journal cleanup and before source activation or Coordinator recovery. The host enumerates bounded retained reservations, proves each owned scratch process stopped, then Store.discardAbandonedReservation journals deletion of only runs/<id> or preparing/<id>. It refuses live execution rows or concurrent Store writes. Transferred committed input/preparation/artifact roots are preserved; releasing the abandoned reservation removes only its accounting links. Repeated recovery is idempotent, and unsupported ownership blocks admission.

### Control row reserve
maximumRecords is the absolute retained row ceiling, including failure/control rows. Normal writes leave recoveryRowReserve rows unused, derived from each current owner's remaining failure-only transitions: queued/running demand/execution2, cancelling1; registering watch1, active4, paused3, stopping1; pending publication1; preflight/accepted Provider action2, mapped1, outcomeUnknown1; active scratch reservation1 for its retirement journal. Ordinary continuation/progress consumes normal capacity; it cannot recycle the failure reserve into new work. Failure writes use this already reserved portion and never exceed maximumRecords. SQLite byte ceiling/failureReserveBytes independently bound physical storage; exhaustion remains explicit recoveryBlocked, never success. Retention scans use the same absolute row bound. Epoch activation uses failure/control admission, replacing only the previous active epoch record transactionally so repeated restarts do not consume an accumulating row per epoch. The targeted quota counterexample is StoreResourcesTests.cancellationAndEpochRecoveryRemainPossibleWhenOrdinaryRecordAdmissionIsFull.

The Store validates abandonedReservationRoot ownership and symlink containment before the host inspects any process marker beneath it. Unknown relative roots and symlink aliases block recovery before physical process operations, not only before deletion.

StoreIntegrityTests replaces the retired schema1 report script by directly corrupting a retained run assessment through the actual SQLite owner, refusing unknown schema without file rewrite, and rejecting database symlinks before touching their targets.

Node reports retain their own acknowledged head keyed by workspace and selected entity. Generations are comparable only within one slot. A node publication preserves the workspace-wide default.
