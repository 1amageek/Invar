# VerificationCore.Domain

## Purpose and Scope
Own immutable input/job/contract primitives and narrow public ports. Changes and Evidence own their specialized records. Parent: [module](../DESIGN.md). No children.

## Responsibilities and Boundaries
No lower-package, storage or process dependency. Exact source bytes are identified with SHA-256; unknown/partial coverage is retained. Plans and evidence retain independent status axes.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Public domain/module contracts | Component owner | Recheck direct consumers on changes |
| [Verification plan](../../../Documentation/VERIFICATION-PLAN.md) | coordinates with | Behavioral acceptance ownership | Test mapping | Mocks do not establish backend semantics |

## Architecture
```text
Validated input -> Domain -> immutable result or typed failure
```

## Contracts and Invariants
A modelGeneration job carries one captured entity and one input file. Its outcome is always notEvaluated. File scope includes the entire file; function scope includes the exact recorded declaration bytes.

Breaking schema-2 implementation. Basic identity/input/job primitives and client domain ports remain here. Change and evidence meaning belongs to the new Changes/Evidence children. PlanBody carries a fixed input reference; evidence owns retained artifact references. Typed transactional ports replace inline backend reports and ephemeral execution tickets. Old serialized forms are rejected; no adapter is added.

Preserve exact input identity, separate execution/property/domain/translation/applicability, and propagate typed failures. Public API is protocol-based; concrete state does not escape its owner.

A validated plan has safe unique job IDs, a bounded acyclic dependency graph, feasible positive resource declarations, an exact inventory content identity and a pinned executor digest. Evidence must match both job identity and backend domain. Unknown status strings are rejected at the worker/store boundary. Input applicability compares all original bytes/context/provider identities, independently of index generation.

### Public client ports
These proposed domain protocols are implemented by VerificationClient; the daemon supplies their authorized operations:
| Protocol | Operations |
|---|---|
| `ChangeTracking` | begin, seal, abandon and inspect fixed change revisions |
| `VerificationPlanningClient` | prepare a plan asynchronously, inspect preparation and sealed plan |
| `VerificationRunningClient` | submit/replay fixed plan, inspect/cancel own run demand |
| `EvidenceQuerying` | read common change view, bounded graph/trace/origin pages and authorized artifact ranges |
| `WorkspaceWatching` | register/update/disable durable authorized watch; inspect its state |
| `WorkspaceEventSubscribing` | subscribe after cursor, explicit resync and shutdown |
| `WorkspaceAdministration` | daemon status/start/stop and policy administration, granted only to host-user principals |

## State, Ownership, and Lifecycle
Invocation-local values or module-owned actors; no shared mutable global or target-specific synchronization. Active resource owners provide explicit shutdown/cleanup.

## Failure, Concurrency, and Constraints
Bound inputs and outputs according to the module contract. Cancellation/resource exhaustion is incomplete, never proof. External callbacks and I/O execute outside short Mutex scopes.

## Verification and Change Impact
Corresponding Invar test targets execute positive and negative behavior and invariant mutations. Changes recheck the parent module and its direct consumers; no completion claim comes from document structure.

Saved-plan decoding applies the same obligation validation as configuration decoding; content hashes alone cannot validate an oracle range, count or mode. Fuzz evidence cannot claim holdsWithinScope.

Configuration identity sorts obligations by stable ID within each backend, since declaration order does not define scheduling. Every saved plan reconstructs that identity from its bound obligations; startup MCP authority uses the same identity.

[SDK transition](../../../Documentation/SDK-TRANSITION.md) owns current implementation facts, exact removal order and acceptance gates.

### Sealed worker descriptors
A `JobDescriptor` contains one validated obligation, its sparse exact input entries, immutable input reference, executor and budgets. It never embeds the complete plan or source/catalog bytes. Plan validation and worker validation use the same per-job contract. Formal/native/fuzz descriptors must name exactly their enforced source/oracle read set, with unique safe paths and digests. The plan binder verifies every sparse entry against the captured manifest before storage. Static descriptors bind the independently audited graph digest. Worker checksum validation detects mutation but does not confer execution permission.

### Daemon authority records
`WorkspacePolicy` is a revisioned host decision binding engine/workspace, approved peer executable identities/capabilities, and exact configuration/oracle/harness/corpus approvals. `PrincipalGrant` records original capability ceilings, credential digest, code identity and expiry. Live session credentials additionally bind the actual OS audit identity. Resuming cannot extend the original grant expiry or add capabilities. Policy persistence is a narrow port; no public namespace/payload writer is introduced.

FormalCheck optionally declares memoryMiB. Its admissionMemoryMiB uses that explicit value, otherwise the named finite/quantified development defaults (1536/2560 MiB). Plan construction and validation bind JobReference/descriptor memory to that exact configuration value; admission refuses it when it cannot fit the host/request. The isolated process monitor enforces the same declared aggregate RSS limit. A resource-limited attempt is not a proof. Actual toolchain integration may select a larger explicit budget and reports observed peak RSS; no silent retry raises the limit.

SourceEventReading is a single workspace-owned metadata cursor. Its SourceEvent keeps source availability, invalidation and continuity loss distinct. A ready event permits requesting a fresh fixed capture; it is not itself captured input or verification evidence.

SchedulingPlan.capturedScopeDigest binds the complete captured input semantic digest, executor, normalized configuration, approved contract entries, run budget and every original job/profile/tool/input/compilation declaration. It excludes only plan/index snapshot identity. It supports exact whole-captured-scope reassociation under a fresh source fence; it is not a shared-job cache key and never removes upstream unknown boundaries. Changed tools, context, raw input/graph/coverage, budget or obligations change this digest.

WatchControlling is the authenticated client port for durable register/stop operations plus per-principal watch records. Registration and stop return normal durable receipts; disconnect detaches observation. Watch queries expose bounded current registrations for the requesting principal and exact historical records by ID, without private source/evidence payloads. Daemon status counts committed registering/active/paused/stopping records from WatchRepository, not an independent in-memory watch list.

VerificationInput.sourceIdentity separates one source authority observation from per-plan contract/oracle extras. For Explorer captures it binds workspace, snapshot, context, graph digest and the single original owner manifest bytes; the authenticated adapter validates those owner bytes. Captures without an owner manifest use the explicitly distinct captured-scope identity domain and retain their full semantic scope, without claiming Explorer authority. semanticDigest/capturedScopeDigest still include every contract/oracle extra and control reuse independently.
