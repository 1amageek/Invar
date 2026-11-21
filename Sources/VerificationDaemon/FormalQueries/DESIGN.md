# VerificationDaemon.FormalQueries

## Purpose and Scope
Own bounded authenticated FormalEvidence readers and retention pins. Parent: [Daemon](../DESIGN.md). No children.

## Responsibilities and Boundaries
Open only bundles retained by an authorized workspace evidence record, answer lower SDK queries unchanged and close/pin-release explicitly. No proof/graph synthesis, source index or client-side Store access.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Daemon](../DESIGN.md) | parent | Lifecycle/control/data split | Composition owner | Close readers before Store |
| [Formal queries](../../VerificationFormal/Queries/DESIGN.md) | depends on | Exact wire/read policy | Public contracts | Session/principal-bound handles |
| [Store](../../VerificationStore/Persistence/DESIGN.md) | depends on | Artifact roots and pins | Immutable evidence ownership | Pin before opening file |
| [FormalEvidence](https://github.com/1amageek/swift-formal/blob/main/Sources/FormalEvidence/DESIGN.md) | depends on | Actual indexed reader | Formal semantics/data | No report-text parsing |

## Architecture
```text
sourceValues session -> evidence/bundle ownership check -> pin -> bounded SDK reader
  -> exact catalog/page/trace/origin/document -> explicit close or expiry -> release pin
```

## Contracts and Invariants
All raw queries require read and sourceValues and use the data listener. Every bundle must occur unchanged in that workspace's immutable evidence record. Reservations count before asynchronous pin/open work. Leases bind principal/session/epoch and cannot be transferred by copying an ID. Client budgets must fit host policy; oversized requests fail before file parsing. Read state never changes verification outcomes.

## State, Ownership, and Lifecycle
The reader registry actor owns open counts, reader instances and pin IDs. Host housekeeping closes expired readers, then releases their pins. Pins include bounded crash-expiry slack; a crashed process has no live file descriptors. Explicit shutdown closes every reader before Store shutdown, reporting cleanup failure. No deinit starts asynchronous work.

## Failure, Concurrency, and Constraints
The development profile allows four leases for two data-plane consumers, with bounded pages/records/cursors/traversal and 60-second maximum leases. Operators may select a validated profile. The RPC data connection cap bounds concurrent query work independently of control capacity. These are logical data/cache bounds, not an instantaneous physical RSS claim. Corrupt bundles, unavailable extraction, expired handles, denied access and output-budget exhaustion remain distinct errors.

## Verification and Change Impact
Use actual bundle identity and paged read tests, private-access denial, concurrent capacity, session isolation, expiry, cancellation during open, shutdown and pin/prune interaction. Recheck Hosting, Store retention and the lower FormalEvidence read implementation when contracts change.
