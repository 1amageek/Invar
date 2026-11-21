# Daemon and evidence SDK transition

[System DESIGN](../DESIGN.md) owns composition. This record owns the implemented replacement/removal decisions; linked leaf designs own contracts. [PROGRESS](../PROGRESS.md) records exact behavioral evidence and remaining task validation. Breaking development changes are intentional; no schema1 migration or compatibility runtime is provided.

## Current implementation and owners
| Behavior | Design owner | Replacement decision |
|---|---|---|
| Workspace lifetime, authenticated IPC and physical recovery | [Hosting](../Sources/VerificationDaemon/Hosting/DESIGN.md) | CLI-owned idle service and internal-service modes removed |
| Frontend sessions, fixed resume profiles and explicit renewal | [Session](../Sources/VerificationClient/Session/DESIGN.md) | CLI/MCP direct Store/preparation removed |
| Durable requests and shared execution interests | [Coordination](../Sources/VerificationRuntime/Coordination/DESIGN.md), [Scheduling](../Sources/VerificationRuntime/Scheduling/DESIGN.md) | Serial whole-plan queue and ephemeral tickets removed |
| Daemon-owned monitoring | [Watching](../Sources/VerificationRuntime/Watching/DESIGN.md) | CLI WatchCommand removed; process exit is no longer watch ownership |
| Fixed references, immutable changes/evidence and bounded retention | [Evidence](../Sources/VerificationCore/Evidence/DESIGN.md), [Persistence](../Sources/VerificationStore/Persistence/DESIGN.md) | Schema1 inline report/submission shapes removed |
| Exact original inputs and independent source observations | [Connection](../Sources/VerificationExplorer/Connection/DESIGN.md) | Per-configuration extras do not redefine source authority |
| Published default and independent operation history | [Publication](../Sources/VerificationExplorer/Publication/DESIGN.md) | Confirmed complete original-generation head is the default; unpublished history cannot replace it |
| Confirmed Provider execution/cancellation | [ProviderActions](../Sources/VerificationDaemon/ProviderActions/DESIGN.md) | Concrete SDK ledger owns the live first-start decision; no synthesized starts on recovery |
| Original structured formal evidence and retained read leases | [Queries](../Sources/VerificationFormal/Queries/DESIGN.md), [FormalEvidence](https://github.com/1amageek/swift-formal/blob/main/Sources/FormalEvidence/DESIGN.md) | Summary/regex-derived graph substitution removed |

```text
Client requests -> authenticated fixed envelopes -> durable demands -> shared workers
Source Actions -> concrete SDK ledger -> atomic original-job mapping -> same workers
Workers -> immutable evidence -> per-operation views -> original-generation outbox
Published complete ACK -> default head; every other result -> retained history
```

## Removal and authority boundary
The obsolete executable WorkspaceService/Watching directories, old CommandDriver preparation helpers, SharedVerificationCoordinator, ExecutionSubmission/ExecutionReceipt and ticket-resubmission tests are deleted. CLI accepts sealed plan/run IDs and explicit idempotency keys. Native/Lean execution permissions belong to actual host policy, not CLI/MCP Boolean arguments or source content.

ArchitectureExplorer and swift-sdk are independently owned, read-only local dependencies. Invar calls their public SDKs through owned fixture processes during integration. It neither writes their databases nor changes the user's running Explorer. Structural publication/SDK reading does not certify the separate GUI renderer or private source-preview mediation.

## Verified behavior and limits
Actual authenticated process tests exercise Source approval, exact capture, source edits, durable watches, original-receipt reconciliation, daemon SIGKILL/worker cleanup, confirmed Actions/cancellation, CLI/MCP lifetime and rooted TLA/Lean/IR evidence queries. Owner tests exercise quota refusal, failure/cancellation recording, retained reference closure and lifecycle races. Test names and scoped measurements live in PROGRESS rather than being copied into this contract record.

Generated-model source correspondence stays UNVALIDATED; graph extraction availability and viewport truncation remain separate from proof axes. V5 Actor semantics and complete source refinement are outside this SDK implementation. Resource monitoring is sampled, not a hard instantaneous memory governor. No release/deploy or GUI acceptance is implied by local build/test evidence.
