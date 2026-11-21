# VerificationDaemon.Workers

## Purpose and Scope
Implemented private worker composition. Own private worker dispatch and executable/resource identity. Parent: [Daemon](../DESIGN.md). No children.

## Responsibilities and Boundaries
Resolve typed admitted worker jobs to actual backend/inspection implementations. Runtime owns admission/process lifetime; Backends and Formal own operation meaning. No public arbitrary executable/shell endpoint.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Daemon](../DESIGN.md) | parent | Worker composition | Entrypoint owner | Private protocol only |
| [Scheduling](../../VerificationRuntime/Scheduling/DESIGN.md) | used by | Bounded resource/deadline lease | Actual execution | No whole plan copied into a worker |
| [Execution](../../VerificationRuntime/Execution/DESIGN.md) | depends on | Verified process identities/journals | Cleanup owner | Recovery before replacement |
| [Backends](../../VerificationBackends/DESIGN.md) | depends on | Method execution | Semantic adapters | No inverse dependency |
| [Inspection](https://github.com/1amageek/swift-formal/blob/main/Sources/FormalValidation/Inspection/DESIGN.md) | depends on | Structured evidence extraction | Heavy formal work | Tool isolation is explicit |

## Architecture
```text
admitted job id + sealed input/artifact access + engine identity
 -> private worker request -> backend/collector -> sealed artifact/evidence references
```

## Contracts and Invariants
Worker requests contain immutable ids, minimum typed job context, approved private access roots, exact tool/executor identities and remaining limits. They do not contain entire queued ScopeInventory/source/report blobs. The worker checks actual parent/group/start identity and input hashes before running. Worker output is an immutable result reference plus bounded diagnostics, not a multi-megabyte stdout report.

Keep trusted build/formal helper groups supervised and inherit ownership into nested tools. Native or user-Lean executable code needs an actually enforced no-fork isolated-session sandbox and durable launch intent/PID identity before resume. The daemon retains ownership of such sessions/journals even if preparation is offloaded. Separate processes alone are not isolation.

## State, Ownership, and Lifecycle
A job owns its request, resource lease and unpublished output staging. Process supervision uses actual UID/start/session identity and exactly-once reap. Completion is visible only after cleanup and Store commit. Worker death yields typed interrupted/tool/resource status, not fabricated success or automatic replay.

## Failure, Concurrency, and Constraints
Bound all request/result/reference sizes, descriptor roots, tool output, workspace/graph bytes, CPU/RSS/process counts and wall/cleanup time. No unapproved imports, project scripts, host fallback or runtime installation. Missing strict isolation capability blocks execution.

## Verification and Change Impact
Planned **ID-03/06, FE-08/09** run actual child overlap, resource exhaustion, launcher crash before PID publication, native/Lean escape denials, owner loss, corrupt requests and complete reap. Existing ToolExecution/ToolLaunchJournal tests remain lower evidence.
