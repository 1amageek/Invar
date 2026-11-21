# Provider Actions

## Purpose and Scope
Daemon component, parent [VerificationDaemon](../DESIGN.md). Owns confirmed Explorer Action delivery, concrete SDK ledger use, and progress reconciliation. No child components.

## Responsibilities and Boundaries
Explorer owns user confirmation and its run generations. The concrete ArchitectureClient ProviderActionLedger owns durable source receipts and the sole live first-start decision. Invar Store owns the mapping to one durable demand. Host principal/configuration/native grants remain mandatory and independent of source approval. No remote RPC admits external demands directly.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Hosting](../Hosting/DESIGN.md) | depends on | DaemonAuthenticating, lifecycle binding | Actual daemon peer authority | Source permission never grants host authority |
| [Coordination](../../VerificationRuntime/Coordination/DESIGN.md) | depends on | consume external start, recover | One SDK job ID is one logical demand | No external restart |
| [Evidence](../../VerificationCore/Evidence/DESIGN.md) | depends on | ProviderActionRepository | Immutable preflight and scalar mapping | Private opaque intent/authority never exposed |
| [Publication](../../VerificationExplorer/Publication/DESIGN.md) | coordinates with | original reservation adoption/check | Same source run as progress | Never allocate a replacement generation |

## Architecture
```text
Confirmed Source Action -> fixed host session/envelope -> original Source run -> immutable preflight
    -> concrete SDK ledger reserve -> receipt ACK + initial unknown state
        -> one in-memory start permit -> Coordinator -> atomic demand/receipt/mapping -> workers
Reconnect -> SDK lookup -> existing mapping/progress or explicit nonrunnable unknown
```

## Contracts and Invariants
The verify-model v2 action accepts empty arguments for source-only generation. The confirmed entity selects the input. A named specification selects the existing checked path.

A confirmed verify-model action binds one source entity, its indexed property file and the exact manifest. Invar prepares a node-scoped formal plan under the host planning and verification grants. The reserved run and all published evidence carry the same entity binding. A repeated delivery cannot start another execution.

Only a freshly dequeued current-session Action may call reserve. Only its returned mayStart=true permits one consumed start. Reconciliation only calls lookup and cannot issue a replacement permit, request, job ID or generation. Verification accepts a sealed plan ID and optional sealed change ID, with no arbitrary path or execution permission flags. Cancellation identifies an original Provider Action and resumes its original private principal under current host policy; it cannot cancel another principal or widen/extend authority. The source binding must exactly equal the retained original manifest and have empty entity/fact selection for workspace verification.

Preflight precedes SDK acceptance and retains the actual source run, envelope, typed operation and opaque original intent/resume secret. Receipt mapping and queued demand commit atomically before physical work. If SDK acceptance survives without mapping, reconciliation records nonrunnable outcomeUnknown; a new user-confirmed Action is required for new work. Missing SDK receipt is explicit unknown, never a first-start opportunity.

## Runtime Flows
Activation follows recovery/open admission. One owned pump polls source Actions and reconciles bounded retained actions; up to32 owned preflight tasks can await worker admission without blocking receipt/progress/cancellation delivery. Source initial unknown revision1 records the real run before Core admission; subsequent reports use Core revision+1. Verification publication adopts that preflight run rather than reserving another generation. Old run rebinding first proves existence/generation through the owner inventory. Ambiguous acknowledgement retries original immutable receipt/state only.

## State, Ownership, and Lifecycle
Actor owns the pump, at most32 preflight tasks, and at most32 live first-start permits, removed on consumption or shutdown. Store owns immutable preflight plus bounded scalar delivery revisions, pinned through the source deduplication deadline+3600. Histories are bounded to512 records and normal storage quotas. Credentials remain private opaque Store data and never appear in summaries, graphs or diagnostics. Stop admission cancels/drains the pump before Coordinator teardown; accepted Core work is separately drained by Coordinator.

## Failure, Concurrency, and Constraints
No external execution resumes after process restart. Pre-acceptance validation/capacity failure is rejected; accepted receipt ambiguity is retained as unknown. Permission/auth/configuration failure cannot start work. Each source call uses the actual SDK bounded RPC. Pump retries transient outages with original identity; source data loss blocks rebinding. Verification preflight acquires shared worker resources before source inventory I/O; cancellation uses the bounded controller plane (one fixed envelope and original private preflight, under128KiB per task) and never waits for the worker slots it must cancel. payloads are bounded (intent16KiB, authority8KiB, run16KiB). Receipt/progress remain bounded scalar controller operations; shutdown drains every owned preflight task.

## Verification and Change Impact
ProviderActionTests must exercise the concrete file-backed SDK ledger (duplicate reservation and reopen), atomic Store mapping/gap handling, no restart, grant denial, cancellation ownership, and original publication generation. Owned Source process tests must prepare/confirm an Action and observe its original SDK receipt and actual worker completion. Changes require Hosting, Coordination, Store and Publication regression checks. No ArchitectureExplorer source changes are owned here.

## Whole-project dispatch

verify-project carries a repository-relative configuration path and one Workspace or C4 subject. WorkspaceOperations verifies the original snapshot and configuration subject, seals a project-only plan, and requires exact host contract approval. The existing ProviderAction ledger maps the confirmed action to one verify demand. Native and user Lean execution grants are required before admission. Project jobs use the existing bounded scheduler and private process journal. Publication remains tied to the original subject and manifest.

Explorer menu -> immediate verification destination -> prepare/confirm -> ProviderActions -> sealed project plan -> scheduler/project command -> receipt validation -> original publication. Failure or cancellation never advances a successful verdict.
