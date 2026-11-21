# VerificationCore.Evidence

## Purpose and Scope
**Schema-2 records, associations and Store views are implemented; daemon/frontend composition remains in progress.** Own immutable verification evidence, current-input associations and one common change-verification view. Parent: [Core](../DESIGN.md). No children.

## Responsibilities and Boundaries
Associate actual results with changes/inputs/obligations and derive explicit scoped assessments. No formal semantics, source parsing, tool invocation or UI styling. Formal graph meaning is owned by FormalEvidence and remains namespaced behind artifact references.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Core](../DESIGN.md) | parent | Domain boundary | Evidence semantics | Schema 2 |
| [Changes](../Changes/DESIGN.md) | depends on | Fixed change revisions and observed deltas | Attribution versus proof | Never infer author from a test |
| [FormalEvidence](https://github.com/1amageek/swift-formal/blob/main/Sources/FormalEvidence/DESIGN.md) | coordinates with | Artifact/graph/claim semantics | Adapter boundary | Core has no Formal import |
| [Store](../../VerificationStore/Persistence/DESIGN.md) | used by | Durable associations and query revisions | Shared truth | No frontend recomputation |
| [Publication](../../VerificationExplorer/Publication/DESIGN.md) | used by | Common view revision | User graph | Rendering cannot upgrade status |

## Architecture
```text
change revision -> plan -> run demand -> shared execution -> immutable evidence
                                                     -> formal bundle references
immutable evidence + scoped dependency comparison -> evidence association
change + associations + coverage -> one ChangeVerificationView -> MCP / Explorer
```

## Contracts and Invariants
| Proposed record | Required fields / meaning |
|---|---|
| `VerificationInput` | sealed source/catalog id, Explorer snapshot and complete original manifest digest, contract/oracle digest, context, backend/profile/tool/executor identities, declared dependency closure and closure coverage |
| `VerificationEvidence` | id, actual obligation/proposition, execution/outcome/domain/translation/scope, assumptions, original input reference, witness/reproduction identity, resource measurements, diagnostics and typed artifact/bundle references |
| `EvidenceAssociation` | evidence id, target change revision/input reference, exact comparison basis, scoped applicability, unknown boundaries and reuse decision; append a new association, do not rewrite old evidence |
| `RunDemand` | durable client/watch/action request and authorization, fixed plan/input, state/revision, execution interests and immutable terminal receipt; distinct from shared worker execution |
| `ChangeVerificationView` | workspace/change revision/input binding, daemon epoch and durable view revision, observed changes, impact/unknown boundaries, obligations/results, evidence associations, coverage, pending/failed attempts, graph catalog references and diagnostics |

Execution, property truth, domain, source/model correspondence, extraction availability, coverage, attribution and current applicability are independent. A completed model proof remains generatedModel/UNVALIDATED until independently certified. Missing/expired evidence or unsupported Actor semantics remains visible; no overall safety percentage is derived.

Reuse requires equality of complete *scoped* read inputs, contract, tools/runtime/executor, backend/profile, seed/measurement settings and relevant budget. Snapshot IDs/session/change IDs do not by themselves prove equality or inequality of semantic inputs. Unknown closure prevents reuse/current certification for that scope. An explicit replay creates a new execution; it cannot return cached evidence as if re-executed.

Explorer's project-level `dependencyStatus=unknown` must be preserved. A restrictive standalone backend may independently establish a complete declared unit closure from an enforced profile; it cannot upgrade the Explorer project closure. Views carry upstream binding applicability and scoped evidence applicability separately. A current source claim requires the closure appropriate to that claim; an exact-file generated-model result never proves the whole project.

Source edits append uncertain/stale associations immediately. Completion of an older run stays historical; changing the association cannot change its original outcome. Replayed failures require the same backend reproduction/witness identity; a different failure is not reproduction, a passing retry is unreproduced, and missing historical witness identity is inconclusive.

`ChangeVerificationView` is computed from one committed Store revision. Agent/MCP and Explorer read that same view id/digest. Queries/export cannot recompute a weaker acceptance policy. An obligation that has no approved oracle, required unsupported method, empty execution or unknown mandatory input cannot satisfy default CI. Extraction failure may hide a graph, never the underlying diagnostic/proof result.

## State, Ownership, and Lifecycle
Evidence and associations are immutable, content-addressed retained records. Run/watch interests and applicability heads are actor/transaction-owned. Readers pin referenced artifacts through their page/subscription lifetime. Retention cannot delete active evidence, unresolved findings, registered baselines or in-flight publication data.

## Failure, Concurrency, and Constraints
Large tool reports/source/graphs are private artifacts, not inline Data copied into every job/IPC record. Result/reference integrity is checked before publication. Unknown typed semantics are rejected; corruption never becomes a default status. Every response is bounded and revision/cursor-bound.

## Verification and Change Impact
Planned **IE-01..06** mutate every input/contract/tool dimension, mix old/new results, compare CLI/MCP/Explorer view digests, preserve native original/reduced witnesses, and test partial graph data with valid proof evidence. Recheck assessment, scheduling, retention and all frontend projections when these semantics change.

### Concrete sealing and association profile
`VerificationEvidence` contains its exact original input ID, obligation, execution/outcome/domain/translation/scope, adequacy, assumptions, diagnostics, measurements and artifact references. Its identity is a domain-separated length-framed digest of these values; encoded IDs are independently checked on decode. Measurements are finalized before publication. Current applicability exists only in `EvidenceAssociation`, never inside or as a mutating operation on evidence. `InputComparison` binds the actual compared target reference (or explicit missing target), status, basis and unknown boundaries. Run assessment consumes those associations and the committed plan; a matching status without a matching semantic input binding cannot pass.
Backend output artifacts are written under private digest-named staging files. The coordinator verifies/imports them before committing terminal evidence. Structured Formal bundles use their exact database SHA and schema; private JSON/native reports are artifact references rather than inline worker/IPC payloads.

### Execution and target bindings
Before publication, the scheduler seals each worker result with its exact `JobDescriptor` ID and independently computed complete-scoped execution key. Store rechecks both from the retained descriptor. A cross-plan association names the target descriptor and can match only when the original and target complete-scoped keys agree. It does not replace the evidence's original input ID. Snapshot/change/plan/session IDs do not enter the key; exact job, sparse bytes, context, executor, tool and budgets do. Static reuse additionally requires audited complete graph closure and graph digest. Unknown closure returns no reusable key. Explicit replay bypasses both live sharing and historical lookup.

Sealed evidence also binds the physical `executionID`. Identical observed results from a fresh replay can share artifact content, but they retain different execution/evidence identities even when wall-clock timestamps have the same resolution. Store checks that the execution owns the original descriptor before accepting sealed evidence.

### Source observation fencing
A committed `SourceHead` owns a monotonic confirmed/uncertain source revision. Invalidation immediately appends an uncertainty assessment without changing original evidence. Assessment history and publication selection have separate owners: commitView appends history only; currentView is the last durably acknowledged complete Explorer publication. PublishedViewHead binds its exact view, provider slot and original generation. Saving a committed publication atomically selects it only if its generation exceeds the retained published head. Older committed/superseded, ready, blocked, partial or failed results remain individual history and never change the default reference. Before the first confirmed complete publication, currentView is nil. Source changes retain that published reference; source uncertainty/applicability is separate metadata, matching Explorer's retained stale publication behavior. A transport-unknown commit is reconciled using its original run before advancing the locally confirmed head; distributed visibility can briefly lead local acknowledgement during a lost ACK, never fabricate confirmation.

Authenticated request envelopes retain the issuing session ID and its capability ceiling. Store verifies that ceiling against the recorded session at issuance; the coordinator intersects it with current principal/policy authority at execution. Resuming a principal through a narrower CLI/MCP session cannot recover omitted native/user-code authority through a request payload. An accepted demand retains its fixed deadline and original scoped grant independently of the observing connection.

`VerificationRunSummary` and `EvidenceSummary` are bounded read projections of already committed records. They carry the original evidence/run references and exact independent result axes, with the original accepted-at-completion flag explicitly historical. They omit raw scope text, source, logs, witnesses/values and unknown measurement fields; scopeDigest identifies the protected scope description. A summary never claims to be the original content-addressed record. Full immutable records stay unchanged and require sourceValues. CI/read consumers use the server-provided committed assessment rather than deriving a weaker verdict.

### Publication delivery ownership
PublicationRecord is a bounded opaque delivery envelope owned by Invar, not an Explorer semantic type. PublicationRepository retains immutable revisions, original input/reservation identity and optional committed ViewReference. The record exists before external begin; ready payload and the common view commit atomically with terminal demand/run. VerificationPublishing reserves before physical scheduling and prepares delivery metadata without changing verification axes. External failure produces a blocked publication record while verification truth still commits.

States are reserving -> reserved -> ready -> committed/delivered/superseded, with blocked terminal failure possible before delivery. Reconnection may replace only the session-bound handle of the original generation; it cannot replace input, run identity, generation or payload. Transient delivery errors retain ready plus a bounded diagnostic.

ExecutionLedger.beginDemandCancellation and finishDemandFailure own atomic durable transitions against the current row, preserving all physical execution interests. Cancellation checks the durable principal before mutation. Terminal failure observes an already requested cancellation; a concurrent revision update cannot be reported as a storage failure.

### Durable watch records
WatchRecord owns fixed registration authority (original accepted envelope, principal, policy revision/capability ceiling, configuration path, budget and original principal expiration). WatchCycle owns scalar generation/phase/pending-demand/prepared-plan metadata; no captured input arrays live in queues. WatchRepository retains immutable revisions, bounds active/paused registrations to32 and retains current envelope/principal/plan/run/view/demand references. Registration requires the original running authenticated watch demand plus current planning/verification/watching grants. Later revisions cannot extend authority or expiration. Stop/expiry is terminal. A paused watch can become active only under the same still-valid pinned policy.

Only current watch revisions are retention roots. Links attach to each immutable revision, never an accumulating pseudo-owner that retains every prior cycle. Behavioral owner: WatchRecordTests. This record/Store contract is separate from the daemon event/derived-demand orchestration owned by Runtime Watching.

Derived watch envelopes are issued by WatchRepository.issueWatchEnvelope only for the retained current cycle stage/configuration/budget/plan. They carry watchID instead of a live session ID and retain the original watch capability ceiling. Ordinary issueEnvelope rejects watchID. WatchRepository.validateWatchRequest rechecks the retained envelope, current registration stage, fixed expiration/authority and typed operation at admission/start/recovery. Same-key cross-agent/watch ownership conflicts rather than widening scope. Accepted watch children have origin=watch and may resume only proven queued internal work under the original deadline; started work remains interrupted.

EvidenceReconciliation owns exact captured-scope reassociation. It requires the original run's nonempty completed evidence set to cover the identical target obligations and the original/target SchedulingPlan capturedScopeDigest to match. It creates new associations to the target descriptors/input with original evidence IDs and prior/upstream unknown boundaries. WorkspaceOperation.reconcile performs no backend/user-code execution; it requires verification plus current exact-contract approval, and commits only a new common view/outbox/demand. Incomplete execution or changed scope rejects this path. Original run/evidence/accepted-at-completion records remain immutable.

Reconcile is a daemon-owned watch-stage operation, not an agent-submitted execution command. The original cycle must retain a completed deterministic preparation child whose result is the target plan, under the watch configuration/budget. The coordinator requires a confirmed current target source fence at admission. Ordinary RPC request.prepare refuses reconcile; watch-envelope acceptance alone admits it. WatchRequestIdentity owns deterministic stage envelope/demand/key derivation for issuance, recovery and cancellation-gap cleanup.

Watch stopping is durable before child cancellation. stopTarget records stopped versus expired independently of diagnostics. Final stop/expiry requires an idle cycle and all recorded/deterministically derivable current-cycle children to be terminal after owned cleanup; a crash gap before pending-demand attachment cannot hide a live child. Stopping registrations remain retention/capacity roots until cleanup finishes.

Each completed RunDemand stores the exact committed ViewReference created by its transaction, independently of whichever view a global/publication selector currently chooses. A watch/client uses that reference instead of racing another operation's current-view lookup. The default reference follows PublishedViewHead; this per-operation reference independently exposes unpublished historical results.

Registration is initially nonrunnable (`registering`). Only the Store transaction completing its original watch demand can activate it. Failed/cancelled/interrupted registration aborts that staged record in the same terminal transaction. Ordinary saveWatch cannot activate a staged registration. A crash between initial staging and parent completion therefore cannot create a runnable watch. Registering records consume capacity and remain retention roots until terminal reconciliation.

A missing demand head is REQUEST_NOT_FOUND; a retained head with missing revision bytes is STORE_INTEGRITY. Watch cleanup treats only the former (and no accepted receipt) as proven absence. Expiration cannot be requested before its fixed clock deadline.

WatchRepository.authorizeWatch rechecks the retained registration against its current fixed principal/policy/expiry without creating an envelope or durable revision. Both verification and reassociation require the deterministic current-cycle preparation demand to be completed and to name the exact target plan, configuration and budget; possession of a workspace plan alone does not authorize a watch stage.

SourceHead retains a representative immutable input plus sourceIdentity, not a selected verification configuration. Confirmed observations with equal sourceIdentity preserve the same fence even when their per-plan extra input closures differ. Reconfirmation after uncertainty still advances the revision. Admission compares sourceIdentity for the source fence; exact per-plan bytes/context/tool/contracts remain independently checked by applicability and reassociation.

WatchRepository.beginWatchStop and pauseWatch atomically read the current revision and persist admission closure before child cleanup. A concurrent stage update cannot turn stop/revocation into a stale-CAS failure. Only stopped/expired or already-stopping records are returned unchanged; authority and expiry checks remain at the Store owner.

EvidenceAssociation.make canonicalizes unknownBoundaries as a sorted unique set before both hashing and storing. Reassociation may encounter an already retained upstream unknown; preserving it cannot create a nonrecomputable identity through duplicate entries. ReassociationTests covers both original empty and already-present upstream unknown boundaries using actual Store/Coordinator/static evidence.

A retained view owns references to every declared plan/run/evidence/input/change/association. A retained run owns its immutable association records as well as its plan and evidence. Published and assessment roots therefore retain the entire reachable closure after ordinary request retention expires; a displayed run/plan ID cannot dangle while its view remains current.

ProviderActionRegistration is an immutable private preflight: original envelope/typed operation/input/source fingerprint, opaque intent/authority/run bytes, original caller run ID and deadline. ProviderActionState retains scalar receipt job ID, reported demand revision and delivery state. ProviderActionRepository owns bounded create/load/update and atomic external mapping. SDK acceptance gaps become outcomeUnknown without a runnable demand. Pins expire at the original source deadline+3600. No indefinite provider-receipt pins remain.

ProviderActionSummary is a read-authorized workspace projection of source request/job ID, delivery/operation state, plan/change/result/view references and diagnostic code. It omits original intent, resume authority, envelope/principal and source/value payloads; Agent clients can inspect UI-origin outcomes without assuming their execution identity.

WatchRepository.finishWatchPause atomically completes pause cleanup only while the current state remains paused and every owned child is terminal. A concurrent stop keeps its current stopping/terminal revision; pause cleanup cannot reopen or overwrite it.
