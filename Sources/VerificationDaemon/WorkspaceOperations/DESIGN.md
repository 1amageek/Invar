# VerificationDaemon.WorkspaceOperations

## Purpose and Scope
Own admitted fixed capture, change open/seal and plan preparation. Parent: [Daemon](../DESIGN.md). No children.

## Responsibilities and Boundaries
Convert workspace operations into immutable Store records using one source authority, the exact change analyzer and plan builder. No UI, ordinary IPC authentication, verifier execution or independent watch scheduler. A captured configuration/oracle is data; approval bits in it never grant native execution.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Daemon](../DESIGN.md) | parent | Workspace composition | Host owner | Shutdown awaits operation cleanup |
| [Connection](../../VerificationExplorer/Connection/DESIGN.md) | depends on | Authenticated leased capture | Original source bytes | No live source fallback |
| [Changes](../../VerificationCore/Changes/DESIGN.md) | depends on | Principal-owned baseline/seal | Attribution is observation | Open claims may overlap |
| [Scheduling](../../VerificationRuntime/Scheduling/DESIGN.md) | depends on | Shared scalar admission | Same pool as verification | Queues contain only request metadata |
| [Store](../../VerificationStore/Persistence/DESIGN.md) | depends on | Captures, preparations, plans | Immutable publication | Failure cannot become an empty plan |
| [Planning](../../VerificationPlanner/Planning/DESIGN.md) | depends on | Fixed input to obligations | Pure plan construction | Missing tools remain explicitly unavailable |

## Architecture
```text
operation ID -> shared resource lease -> fixed source lease + bounded contract capture
  -> open baseline / exact observed seal / prepared units + sealed plan
  -> durable result -> owned scratch cleanup -> resource release
```

## Contracts and Invariants
A source-only plan binds one file, free function or supported Swift declaration from the confirmed snapshot, with its recorded language, file digest, and declaration range. Generation reads that sealed input and has no user-code, toolchain or oracle execution.

Node model checks resolve an indexed Verification/<entity ID>/properties.json or the unambiguous declaration name. The captured specification and source are bound to the plan. An unspecified condition can yield a generated, unverified model.

A change records the originating request and descriptive claim. The baseline and after-capture are stored before returning open/sealed records. Concurrent baselines are compared with the same after-capture to detect overlaps. Paths and hashes come from captures.

Configurations and nonindexed oracle/corpus inputs are captured by a bounded no-symlink workspace adapter before planning, tagged as independently captured contract inputs. If a path also occurs in the Explorer source snapshot, its exact bytes must agree. Already sealed inputs are never reread from the live filesystem. A plan associated with a change uses that revision's after-input, and fails if its configuration was not captured. Public begin-change can name its configuration; the daemon's configured default is optional.

Pure Formal compilation uses the public SDK and exact source language/digest binding. After Store reserves capacity, preparation creates its unique runs/<demand> scratch parent before Formal performs its atomic sibling-directory publication. Each new compilation writes to unique admitted scratch, then Store atomically adopts its sealed content into prepared/<key>; concurrent identical units converge without overwriting. NativeToolchain.identity inventories and hashes the declared installed environment without invoking the compiler. The native backend consumes the sealed tool identity and exact captured contract bytes. Tool unavailability is recorded explicitly in the plan.

## Runtime Flows
Open captures and observes a baseline, then persists the principal-owned ChangeRecord. Seal checks ownership, captures the current source plus the baseline's independently captured contract paths, computes exact before/after bytes and overlap observations, and atomically seals one revision. Repeated seals return the retained revision. Preparation reads a fixed sealed capture or creates one, compiles required scalar units under remaining deadline, resolves exact tool identities and stores the plan plus bounded DAG metadata.

## State, Ownership, and Lifecycle
Operation tasks are owned/cancelled by WorkspaceCoordinator. Shared resources are acquired before input catalogs/compiler data are materialized. Store owns capacity reservations through adopted content publication and cleanup. The operation scope removes its private scratch and releases its reservation before returning; asynchronous cleanup is awaited even under cancellation. Shutdown closes admission and awaits all admitted callers through the coordinator.

## Failure, Concurrency, and Constraints
Capture profile is bounded by source catalog64 MiB, original files64 MiB, individual source5 MiB and individual contract256 KiB. Declared controller operation memory is1024 MiB; scratch/process bounds come from the request/host profile. This is logical admission, not an instantaneous OS RSS guarantee. Bounds, stale source, missing captured contract, unsafe path, conflicting seal, native tool or input mismatch and failed publication/cleanup return typed errors.

## Verification and Change Impact
Behavioral tests own configuration/source disagreement, historical planning after live edits, principal isolation, exact baseline/seal deltas, overlap classification, shared admission, read-only tool inventory and native execution denial, preparation convergence and cleanup. Recheck Hosting, source adapter, Store and Planner on these contracts. A source fixture is not evidence of actual Explorer transport; separate private-workspace E2E owns that boundary.

### Quiet watch probes
WatchInputProbing performs a resource-admitted, nonpersisting read of the current fixed source/configuration/oracles/harness/corpus and exact installed tool identities against a retained plan. It writes no envelope/demand/input/view/reservation rows and runs no compiler/checker. Thus quiet periodic probes cannot exhaust the evidence ledger or publish generations. A changed/missing tool identity is an observed change; invalid/corrupt tool data throws explicitly. The watch owner persists uncertainty after observing change/failure and before a fresh durable preparation/verification demand. Source-event invalidation remains immediate and independent of probes.

Watch registration/stop is intercepted by the managed Hosting composition before WorkspaceOperations. This adapter owns capture/preparation/probes only and rejects any misrouted watch request as INVALID_REQUEST.
