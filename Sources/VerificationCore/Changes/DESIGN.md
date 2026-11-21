# VerificationCore.Changes

## Purpose and Scope
**Implementation in progress; behavioral evidence and remaining gates are recorded in PROGRESS.md.** Own observed changes, Agent claims and their immutable evidence bindings. Parent: [Core](../DESIGN.md). No children.

## Responsibilities and Boundaries
Define what changed and how attribution is represented. No file editing, source parser, Git-based author inference or execution. Discovery computes observations; Store persists them; Runtime owns lifecycle.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Core](../DESIGN.md) | parent | Immutable domain and ports | Shared meaning | Target schema 2 |
| [Discovery Changes](../../VerificationDiscovery/Changes/DESIGN.md) | used by | Exact observed-delta model | Difference computation | Unknown correspondence stays unknown |
| [Evidence](../Evidence/DESIGN.md) | coordinates with | Change/run/evidence associations | Shared Agent/UI view | Claim is not proof |
| [Coordination](../../VerificationRuntime/Coordination/DESIGN.md) | used by | Durable change transitions | Work owner | Persist before returning ready |

## Architecture
```text
Agent claim + fixed baseline -> open change
     -> coherent after snapshot -> observed delta -> sealed change revision
                               -> attribution/conflict assessment
sealed change -> immutable plan/run/evidence associations
```

## Contracts and Invariants
| Proposed record | Required semantics |
|---|---|
| `AgentSession` | daemon-issued id, authenticated client principal, optional Codex/Claude label, granted scope, policy revision and expiry; caller label alone is not identity |
| `ChangeRecord` | workspace/id, Agent claim or unattributed origin, requested scope, fixed baseline reference, lifecycle revision and current sealed revision id |
| `ChangeClaim` | claimed intent, declared paths/entities, optional patch digest and expected post-file digests; descriptive data, never an oracle/permission |
| `ChangeRevision` | immutable id/parent, before/after captured input references, observed delta digest, attribution assessment, diagnostics and evidence associations; input mutation creates another revision |
| `ObservedDelta` | inserted/removed/modified files with before/after hashes and byte/line hunks, added/removed/changed raw entities/facts, context/coverage/oracle changes and explicit unknown boundaries |
| `SubjectReference` | workspace, snapshot, entity/fact id or exact path/digest/range; old deleted subjects remain references to the old snapshot |
| `SubjectCorrespondence` | before/after subject references, producer, basis and precision; unknown/ambiguous is explicit; no display-name matching |
| `AttributionAssessment` | claimed, claimMatched, overlapping, external or unknown; basis and overlapping change ids; none of these attests exclusive filesystem authorship |

Baseline capture includes dirty/staged/untracked approved inputs and context; a Git commit alone is insufficient. Git metadata may be recorded as provenance, never substituted for captured bytes. The Agent waits for state `open` before editing. If an explicitly requested baseline is unavailable or changes during acquisition, opening fails; no newer baseline silently replaces it.

```text
opening -> open -> sealing -> sealed
                    └─────> conflicted
opening/open/sealing -> abandoned
sealed/conflicted -> new immutable revision (never edit prior bytes)
```
`conflicted` retains the actual after snapshot and observed delta; it is not a successful attribution claim. Sealing the same request is idempotent; altered inputs with the same request key conflict. Unregistered filesystem edits create unattributed observations. Concurrent claims on the same files/ranges are marked overlapping. Even matching patch digests do not prove which process wrote a file; Invar does not introduce an editor or mandatory write broker.

## State, Ownership, and Lifecycle
Records are immutable Sendable values. Daemon/Store own revisions and pins. Closing an Agent connection does not erase an open/sealed change or another client's execution. Abandoning releases active work interests but keeps retained historical observations under policy.

## Failure, Concurrency, and Constraints
Bound open changes, claim/hunk bytes, subjects and capture jobs by host policy. Unsupported matching precision remains explicit. Never broaden an Agent claim into ownership of all edits observed since a timestamp. Source changes during a comparison produce retryable INPUT_CHANGED, not mixed before/after data.

## Verification and Change Impact
Planned `ChangeTrackingTests` **IC-01..05** cover dirty baselines, Unicode hunks, concurrent Agents/user edits, ambiguous rename/deletion, changed baselines and repeated/conflicting seal requests. Recheck Discovery, Runtime, Store and Client when attribution/identity semantics change.

A ChangeRecord binds an immutable ownerPrincipal independently of its optional descriptive session. Sealing requires that principal; public origin/claim fields never authorize modifying another change. Concurrent open records remain visible to the change-analysis owner for conservative overlap observations.
