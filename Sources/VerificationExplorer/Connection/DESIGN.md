# VerificationExplorer.Connection

## Purpose and Scope
Own shared-daemon snapshot/lease adaptation. Parent: [module](../DESIGN.md). No children.

## Responsibilities and Boundaries
Use ArchitectureSnapshotReading to enumerate independently paged facts and capture complete original files. Validate cursor/schema/digest/length; release leases on all exits.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Public domain/module contracts | Component owner | Recheck direct consumers on changes |
| [Verification plan](../../../Documentation/VERIFICATION-PLAN.md) | coordinates with | Behavioral acceptance ownership | Test mapping | Mocks do not establish backend semantics |

## Architecture
```text
Validated input -> Connection -> immutable result or typed failure
```

## Contracts and Invariants
**Authenticated replacement implemented; actual transport evidence is recorded in PROGRESS.md.** Use one authenticated aex-1.3 Provider session and a single owned fixed-snapshot input lease across raw scans and byte acquisition. Validate the canonical owner InputManifest digest independently from every copied source digest. Preserve raw namespace/provenance/coverage and upstream unknown dependency status. Use public typed manifest/acquire/read/renew/release ports; no unauthenticated daemon.hello capability/legacy-read fallback. The daemon owns session/reconnect/leases; no frontend launch/capture path survives.

Preserve exact input identity, separate execution/property/domain/translation/applicability, and propagate typed failures. Public API is protocol-based; concrete state does not escape its owner.

## State, Ownership, and Lifecycle
A daemon-owned ProviderConnection actor owns registration, heartbeat, resumption and leases. Every capture releases/renews its single lease through explicit async cleanup. Immutable local copies are sealed before release; failure cannot read the live workspace instead.

## Failure, Concurrency, and Constraints
The actual aex-1.3 typed input/query ports must expose the same leased snapshot across raw scans and original bytes. A convenience helper owning a separate lease cannot substitute for this capture. Revocation, resync, expired lease, changed inputs or unsupported lower capabilities fail explicitly; no second index is started. Preserve provider project unknown separately from independently established scoped backend closure.

Bound inputs and outputs according to the module contract. Cancellation/resource exhaustion is incomplete, never proof. External callbacks and I/O execute outside short Mutex scopes.

## Verification and Change Impact
Corresponding Invar test targets execute positive and negative behavior and invariant mutations. Changes recheck the parent module and its direct consumers; no completion claim comes from document structure.

[SDK transition](../../../Documentation/SDK-TRANSITION.md) owns current implementation facts, exact removal order and acceptance gates.

### Concrete fixed-snapshot input adapter
`ExplorerInputReading` is the narrow leased-source contract. `AuthenticatedExplorerInputs` wraps one aex-1.3 ExtensionProviderClient session; it refuses missing graph/input grants, requests InputManifest using the same lease ID and validates the owner digest independently from file bytes. `ExplorerSnapshotReader` no longer discovers/starts/indexes a source daemon. It acquires one lease, preserves the raw manifest and all raw collection records, scans and copies only that snapshot, renews inline while active, and releases exactly once through an awaited uncancelled cleanup task. Failure to release propagates as cleanup failure. A cancelled/revoked capture cannot reconnect its in-flight lease or substitute live files. The source manifest remains in originalRecords; Invar's inventory identity is distinct from its canonical AEX digest.

### Workspace source-event cursor
ExplorerSourceEvents implements Core SourceEventReading over authenticated events.poll. One actor retains the Provider session, source epoch/snapshot/generation and extension cursors. Source epoch/session gaps, regressed/skipped generations, pending analysis and transport loss produce an explicit invalidation/resync observation. Extension-only updates (including Invar publications) advance only extension cursors and do not invalidate source. Unknown/malformed event shapes fail explicitly. The response profile is bounded16 KiB and contains no source values. SourceEventReading performs no indexing, capture, planning or execution; the daemon watch owner consumes it and persists uncertainty before admitted replacement work.

A successful Provider registration remains owned as pending initialization until grant validation and private resume-record synchronization complete. Initialization failure disconnects that exact session before reporting sourceOffline/approvalRequired. If disconnect itself fails, the connection retains a cleanup-only handle, admits no provider/source use or replacement registration, and retries cleanup during explicit shutdown. Shutdown clears session handles only after confirmed disconnect. The owned real-process connection-failure fixture verifies post-registration filesystem failure against an unmodified Explorer host; it does not modify the user's running Explorer.

Whole-project execution captures the complete leased input manifest and exact bytes plus one source-owned subject. It does not scan every structural entity/fact/evidence record, because project checkers consume files and the complete acceptance manifest. The graph closure remains explicitly partial. Project preparation and applicability use this same profile, so idle observation cannot monopolize raw structural scans before an action starts. Lease cleanup, chunk digests, counts, byte limits and snapshot identity remain enforced.
