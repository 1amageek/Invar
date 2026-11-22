# VerificationRuntime.Scheduling

## Purpose and Scope
Own resource-bounded ready-job admission across workspace run demands. Parent: [Runtime](../DESIGN.md). No children. **Target replacement for the one-active-run scheduler and serialized whole-plan tail.**

## Responsibilities and Boundaries
Schedule actual causal jobs, execution reuse and resource leases. No semantic checking, authorization expansion, source indexing or independent UI queue.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Runtime](../DESIGN.md) | parent | Workspace budgets | State owner | All daemon-owned work is charged |
| [Coordination](../Coordination/DESIGN.md) | used by | Run/watch interests | Shared execution | Session lifetime is irrelevant |
| [Evidence](../../VerificationCore/Evidence/DESIGN.md) | depends on | Scoped reuse and assessments | Cache semantics | Unknown closure cannot be reused |
| [Workers](../../VerificationDaemon/Workers/DESIGN.md) | depends on | Bounded process operations | Actual execution | Cancellation requires reap |

## Architecture
```text
multiple admitted plan DAGs -> shared ready jobs -> priority/fairness + resource leases
    -> worker executions -> durable evidence -> per-demand associations
```

## Contracts and Invariants
`ExecutionKey` binds complete scoped input closure, oracle/contract, method/profile, environment/tool/executor/resource identities, measurement settings and seed. It excludes observer/change/session identity. Reuse of an incomplete/unknown closure is disabled. Explicit replay includes a fresh execution nonce. Equal keys can share one live execution while preserving distinct run/change/input associations.

No global whole-plan tail serializes unrelated requests. Ready independent jobs overlap when reservations fit; exact successful prerequisite assessments are required before dependent jobs start. A cycle or failed prerequisite is a terminal blocked result. Priority classes follow explicit user operations, known reproduction, mandatory contracts and change-local/background candidates; bounded aging/fair sharing prevents indefinite starvation. Reasons are queryable.

Admission accounts controller and input/index/page caches, workers and descendants, request/output buffers, artifact scratch, persistence/recovery reserve and cleanup. Queues retain IDs only. Effective budget is the minimum of user policy, backend capability, measured supported profile and remaining ancestor deadline, with infeasible work rejected before execution. Memory/CPU/process/scratch reservations are released only after durable result and owned cleanup.

A reservation is a logical admission guarantee. Current macOS process sampling is not an instantaneous physical-memory quota; reported measurements disclose sampling and overhead. A requested stronger enforcement capability must be supported or rejected explicitly. Per-workspace budgets do not claim to bound unrelated processes or other workspace daemons.

Wall deadlines produce timeout; resource caps produce resourceLimited; cancellation is separate. A child receives remaining parent time including a reserved cleanup interval. Cancellation propagates to real process owners and awaits completion. Control/status/event handling does not run compiler, tool inventory or giant graph parsing inline.

## State, Ownership, and Lifecycle
Scheduler actor owns ready/running maps, resource leases, priority age and per-demand dependency progress. Short synchronous counters may use Mutex; no await/I/O/callback under a lock. Captures, inspections and tool/hash preflights are bounded jobs with separate read-only versus execution capabilities. Shutdown drains these too.

## Failure, Concurrency, and Constraints
Policy owns worker/process/CPU/memory/scratch/output/queue/default limits, their allowed ranges and measured profile selection. Changes require contention, cold-start and complete cleanup tests. Disk reservation failure returns resourceLimited before launching work; it is not an endless queued state. No GPU execution is implied.

## Verification and Change Impact
Planned **ID-03/06, IE-02/03** measure independent cross-plan overlap, exact predecessor ordering, shared work, replay non-reuse, priority/starvation, aggregate controller/worker resources, deadline/resource distinctions and cancellation under output/disk pressure. Existing within-plan overlap tests remain evidence only for their current path.

### Concrete shared admission and execution profile
`SchedulingPolicy` is supplied by the daemon and bounds live physical jobs, aggregate declared worker memory/process/scratch capacity, ready entries and scratch files. Its development values derive from the existing two-worker backend profile. Controller/cache memory is a separate host reservation; these values do not claim an instantaneous OS RSS limit. Ready queues retain execution/descriptor IDs and scalar resource declarations. Admission uses priority with a bounded number of bypasses, then the oldest request, so an infeasible request is refused and a feasible old request cannot starve. Cancellation removes only the caller's interest; the last interest cancels and awaits the physical worker before reporting terminal cancellation.

Each execution has a stable ID used by both its durable record and private output directory. The queued execution record exists before resource acquisition, the running transition commits before tool launch, and evidence/terminal execution commit atomically after artifact adoption. Resource and disk reservations remain owned through cleanup and publication. A terminal evidence cache is consulted only for complete scoped keys; replay bypasses cache and live sharing. Per-demand DAG admission still bounds that demand's workers and memory. The daemon composes independent plans on the same pool rather than awaiting a whole-plan tail.

### Sealed DAG metadata cutover
`SchedulingPlan` retains only bounded DAG/job references, immutable input/executor/budget metadata and a captured-configuration digest. `JobReference` supplies assessment/admission fields and the sealed descriptor/key identity. Both are content-checked Store records produced with the full plan once. Waiting runs/jobs do not retain decoded native/formal configurations or sparse file catalogs. Full descriptors are decoded only after physical resource admission. Source comparison consumes the scheduling metadata, not the full plan.

An execution interest is appended to its durable demand before the worker becomes runnable. First and later consumers retain separate interests in one execution. A cancelled demand cannot attach a new interest; removal of the last interest cancels/drains the physical owner and commits its terminal metadata. Queued/executing IDs remain queryable even if result publication later fails. Terminal persistence failures use bounded reserved failure records, never a fabricated successful evidence result.

Source capture, exact change analysis and plan preparation acquire the same `WorkspaceResourceAdmitting` pool as backend executions. The daemon constructs one pool and injects it into both operation services and the scheduler; neither creates a private queue that bypasses aggregate capacity. `ResourceRequest` contains only an owner ID and scalar memory/process/scratch/priority declarations. Release follows awaited work/publication cleanup. The host's connection/credential/DAG controller allowance is bounded separately by its connection/demand/metadata caps.

Publication metadata work uses the same pool with positive memory and zero child-process/scratch reservations. ResourceRequest permits nonnegative process/scratch counts; physical backend jobs still declare their positive needs. Zero does not bypass the worker-slot or memory limits.
