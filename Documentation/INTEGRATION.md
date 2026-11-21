# Local integration and ownership

## Confirmed implementation facts

| Lower owner | Public contract consumed | Evidence |
|---|---|---|
| ArchitectureExplorer | ArchitectureQueryClient and ArchitectureSnapshotReading; raw independently paged records and lease-held original bytes | SnapshotAccessTests; input SDK commit `73ccfe7` |
| swift-formal compiler | SourceArtifactGenerating and SourceArtifactGenerator; exact-source auditable artifacts | ArtifactGenerationTests; commit `d62e3a8` |
| swift-formal validation | ModelVerifier/PropertyVerifier, pinned offline tools, owned ToolExecuting sessions/limits/journal | Real TLC/Lean CLI integration and lower ToolExecution/ToolLaunchJournal tests; commit `c91a442` |
| User-selected swift-sdk | MCP Server and bounded StdioTransport | Actual stdio initialize/list/call/EOF; transport tests; commit `6cdd633` |

GraphView projections and source.read previews are not full verification inputs. Formal units are whole accepted standalone Swift/Rust scalar files. Native units are explicitly declared captured Swift modules plus an independent JSON-oracle harness. Native compilation does not require successful structural parsing.

## Parallel development boundary

The user assigned ArchitectureExplorer extension development to that project. Invar does not implement or modify ArchitectureExtensions, registry/session/permissions, ActionIntent dispatch, extension persistence or the Web renderer. The earlier additive input SDK was committed separately as `73ccfe7`. No live user Explorer server is restarted by verification. The current owner aex-1.3 contract requires aex-1.3 negotiation, connection-bound principals and atomic run publications; Invar does not claim compatibility until the owner exposes and verifies that API.

After extension edits began, the mutable development package graph encountered their work-in-progress compile errors. That earlier integration verification used an exported copy of ArchitectureExplorer `73ccfe7` and local Formal and swift-sdk dependencies. The public package now pins all three upstream repositories and is installed through Mint. The earlier verification applies to the revisions it exercised.

## Remaining integration gates

| Gate | Owner | Completion evidence still needed |
|---|---|---|
| Rich Explorer integration | Explorer extension owner, then Invar adapter | Verified public registration/permission/action/event contracts, generic renderer, then actual Invar action/projection E2E |
| Full retention/admission accounting | Invar Store/Runtime | Total historical DB/WAL/input/artifact quota, reference-aware pruning and controller resource accounting |
| V5 semantics | Lower semantic provider/formal owner | Checked multi-module/Actor semantics and source/model correspondence; cancellation/failure/retry/fairness fixtures |

No unavailable capability is replaced by a fabricated graph, semantic model, successful empty result or unchecked host execution.

## Target boundary

The [SDK transition](SDK-TRANSITION.md) consumes current authenticated aex-1.3 contracts and the proposed [FormalEvidence](https://github.com/1amageek/swift-formal/blob/main/Sources/FormalEvidence/DESIGN.md). Existing exported-checkout tests do not certify this new integration. Generic structural graphs and private artifact/query mediation have separate gates. Invar will not edit the concurrently developed Explorer runtime or renderer.

The extension owner has committed the aex-1.3 implementation (`bbd3f5d`; inspected HEAD `8fc4576`). Target design now consumes that committed SDK, including ProviderActionLedger first-start permits. Invar integration/E2E remains pending; earlier exported-checkout evidence is unchanged in scope.
