# VerificationExplorer.Publication

## Purpose and Scope
**Implementation in progress; actual publication evidence and remaining gates are recorded in PROGRESS.md.** Own conversion of a committed Invar view/formal graph slice to authorized aex-1.3 contributions. Parent: [Explorer adapter](../DESIGN.md). No children. Explorer registry/renderer implementation is owned separately and is not changed here.

## Responsibilities and Boundaries
Bind source changes, formal artifacts and evidence to one input/run/view revision; publish generic graph/table/timeline/annotation data. FormalEvidence owns formal graph semantics. Explorer owns authorization, contribution validation, generation/publication head and UI layout/navigation.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Adapter](../DESIGN.md) | parent | Source/provider connection | Integration owner | No direct host DB access |
| [Evidence](../../VerificationCore/Evidence/DESIGN.md) | depends on | Common ChangeVerificationView | Same Agent/user truth | No recomputed verdict |
| [FormalEvidence](https://github.com/1amageek/swift-formal/blob/main/Sources/FormalEvidence/DESIGN.md) | depends on | Graph/origin/trace catalog | Semantic data | No JSON/report-text inference |
| [AEX API](https://github.com/1amageek/ArchitectureExplorer/blob/main/Documentation/EXTENSIONS-API.md) | depends on | Current aex-1.3 typed Client | External boundary | Working-tree contract, owner E2E gate |
| [Store](../../VerificationStore/Persistence/DESIGN.md) | depends on | Outbox and retained view revision | Retry/restart | Separate receipt owner; explicit reconciliation |

## Architecture
```text
AEX begin reservation before work -> Invar work -> committed view
 + bounded FormalEvidence query -> projection with exact input/evidence ids
 -> prepare/stage -> commit complete bundle
 -> architecture / TLA specification / states/trace / Lean dependencies
```

## Contracts and Invariants
A partial Swift expression graph may expose emitter-defined structural labels, line numbers and local arithmetic-check outcomes. The projection excludes arbitrary expression text and retains the unverified whole-node outcome.

Generated-model graphs include the emitted program control flow and carry notEvaluated through projection and publication. Generation never supplies condition evidence.

Daemon owns registration, heartbeat/resume credential and Provider session, independently of Agent/MCP lifetime. Permissions are only those granted by the actual host. Inputs and ActionIntent bindings use the owner SDK's canonical manifest digest; Invar's private context/execution key is a different digest. Do not synthesize credentials or fall back to unauthenticated input reads.

Proposed `ExplorerPublishing` receives a committed view reference, projection query, allowed disclosure and a prepared publication reservation. Return a typed publication result or outbox failure. One immutable projection id binds workspace, source snapshot/manifest, change revision, run/evidence bundle digests and query. It is present in both MCP view and all contribution envelopes.

Reserve AEX slot generation with runs.begin before result work. Reuse its original reservation for delivery/reconciliation; do not obtain a newer generation when an old run finishes. Persist begin/prepare/manifest/commit identities in the outbox. Stage all graph/table/timeline/annotation kinds and commit once. Complete data with a violated or unproved logical claim is not a successful proof; incomplete/unknown *execution or publication* never advances the complete head. A late superseded result stays in Invar history and does not roll back the host head. Outbox failure never rewrites verification truth.

Projection uses namespaced formal node/edge ids and source bindings; it does not add formal edges to the core ArchitectureIR graph. Node kinds distinguish TLA module/variable/operator/action/invariant/state and Lean definition/type/lemma/theorem/axiom/opaque boundary. Preserve edge meanings and exact trace order. Kernel proof, finite exploration, unproved, unavailable and stale states remain separate details; colors alone carry no claim.

Budgets use negotiated host caps: currently graph 500 nodes/1500 edges, contribution 1 MiB, publication 2 MiB and declared view payload 64 KiB. Select a bounded root/neighborhood/trace window with explicit frontier and counts. A shown subgraph never implies the entire model was explored. A giant DOT or full proof term is queried from FormalEvidence, not embedded wholesale. Summary nodes state aggregation/omission explicitly.

Preserve user pan/zoom/layout/selection. Core-source navigation requires exact snapshot/entity or path/digest/range correspondence, not display names. Deleted/ambiguous origins remain historical/orphan. Compiler origin is labeled unvalidated provenance, not a checked semantic-equivalence edge.

### Source/value disclosure and external capability gates
Default publications contain structural labels/statuses and artifact references, not complete source, private logs, arbitrary state values or credentials. Agent artifact-range reads are separately authorized by the Invar SDK. Private artifact ids may appear as literal metadata, but cannot be invented workspace-relative artifactList paths; emit an actual artifactList entry only for a genuinely permitted workspace-relative resource. The current AEX renderer only displays artifact reference metadata and core source navigation; it does not fetch private Invar files. Full live generated-Lean/TLA source preview or interactive remote slice requests require an owner-provided typed mediation capability. This is an explicit integration gate, not a promise to use arbitrary URLs, symlinks or hidden external execution actions. Structural graph publication does not depend on that extra capability. Offline exports preserve the same disclosure policy and disable live actions.

## State, Ownership, and Lifecycle
ProviderConnection owns credentials/session and heartbeat; the daemon ProviderActions component owns confirmed Action delivery. Outbox owns immutable manifest/projection records and retries with current authority. A reconnect reauthorizes and obtains a new publication id for allowed uncommitted work while preserving its generation/input; old staging/leases do not transfer. Shutdown disconnects/releases host resources after owned work cleanup.

## Failure, Concurrency, and Constraints
APPROVAL_REQUIRED/revocation is a visible paused capability, never an execution grant. SDK graph/read/write budgets, busy, expiry, superseded and resync errors are handled explicitly. Own publication events are filtered from input invalidations. Unknown host applicability remains visible beside scoped Invar applicability; project dependency unknown is never overwritten.

## Verification and Change Impact
Planned **IV-01..06** compare MCP/Explorer view digests, source links/Unicode offsets, actual TLA states/ordered counterexamples and actual Lean dependencies, large graph frontiers, atomic multi-view updates, stale/late runs, own-event loops, permission revocation, safe offline export and unsupported artifact-preview capability. E2E uses the separately completed owner SDK/renderer; no lower implementation is modified by this design task.

Action receipt ownership and restart behavior are defined solely by [Coordination](../../VerificationRuntime/Coordination/DESIGN.md), including the required concrete ProviderActionLedger and its nontransactional Store boundary.

### Concrete structural graph projection
FormalProjectionContext validates that the bundle belongs to an evidence record in the committed view, preserves the original EvidenceSummary axes and computes the shared ViewReference once. Its source binding is the independently validated AEX manifest/snapshot binding, never Invar's inventory digest.

FormalGraphProjector consumes an original bounded FormalEvidence page/descriptor. It namespaces all identities by bundle/graph/original ID, preserves edge kinds and producer-declared roots, and carries page/selection/scope completeness independently. Raw state values, expression bodies, source text, arbitrary attributes and opaque private cursors are excluded from the default structural projection. Safe declaration identifiers remain labels; expression/state nodes use structural labels/recorded indices. Original object/document IDs remain references for separately authorized SDK reads. No display-name matching creates source links.

A projection is its own immutable identity bound to the common view digest, exact owner source binding, original page/descriptor content and canonical query scope (roots/relations/direction/depth). Per-reader input/output cursors are excluded from content identity and disclosure. Query scope is bounded to128 roots/64 relation kinds/depth1000000, with explicit failure above that structural projection profile. It does not claim that redacted output has the original bundle digest. Unavailable extraction is a typed unavailable result, not a successful empty graph. The publication owner reserves its generation before work and stages this projection through the durable outbox; a pure projection alone is not evidence of publication or UI rendering.

Node-bound verification annotations carry one condition record per supported generated-model claim in the evidence catalog. The record links the bundle, claim, obligation, model entry, backend, individual outcome, scope and translation status. Quantified conditions disclose the authored precondition and postcondition. Finite cases disclose the expected termination status and retain concrete arguments and values in the evidence store. These records describe the checked contract independently of the structural model pages. Explorer owns graph presentation. For a quantified Swift entry, the approved compilation and captured source digest bind positional inputs to declaration names. Direct calls with matching labels and arity supply syntax candidates and UTF-8 argument ranges in the same snapshot. No caller expression bytes enter the publication. Bounded or ambiguous lookup is explicit and never changes proof status.

### Concrete durable delivery
ExplorerPublisher owns the actual authenticated Provider begin/prepare/stage/commit calls through ExplorerConnecting. It records a deterministic original run key before begin, persists the returned generation/handle, and rebuilds only session-bound staging with the same original run key after reconnect. A different generation is rejected. A committed begin response reconciles a lost commit acknowledgement without restaging. PUBLICATION_SUPERSEDED is terminal history; transient transport failures keep ready payload for bounded periodic retry. Startup blocks abandoned pre-result reservations and drains only ready immutable outbox records.

Default output consists of a small graph of original safe evidence summaries and bounded original formal graph slices (up to eight). Unavailable/truncated graphs are explicitly listed in metadata. Failed/incomplete execution uses a non-complete publication completion, so it cannot advance the complete head. All logical outcomes retain their separate axes. No source text, arbitrary paths, state values or proof expression bodies are sent.

### Default view selection (confirmed user decision)
The Agent default currentView follows the acknowledged complete Explorer head, ordered by the original reserved generation rather than result completion sequence. PublicationRecord retains the opaque owner slot. Store atomically commits the delivery acknowledgement and PublishedViewHead; a lost ACK retains the previous confirmed reference until original-run reconciliation. Per-demand view references retain unpublished/partial/failed and late results as history. Source invalidation appends assessment history and does not substitute an unpublished default view.

Before reconnecting an original publication, OriginalPublicationChecking proves that its original run ID, slot and generation remain in the owner attempt inventory. Absence is ORIGINAL_RUN_LOST, a terminal blocked history; begin must not allocate a replacement generation. The bounded owner inventory is paged with cursor-cycle and page/record bounds.

Provider-origin verification adopts the immutable preflight runRequestID and actual handle, proving its original generation before rebinding; the Core SDK job ID remains a separate demand ID. PublicationRecord retains runRequestID independently of its demand ID.

A node-scoped demand reserves a distinct publication slot for that entity. All reports and formal graphs share its fixed binding. The annotation carries the original outcome, domain, scope, translation status and evidence ID. Recovery reuses the reserved slot; workspace runs continue to publish workspace graphs.

Source-only generation publishes a bounded attempt diagnostic for rejection by the compiler source profile. The manifest carries this public diagnostic separately from incomplete contributions and the verified head.
