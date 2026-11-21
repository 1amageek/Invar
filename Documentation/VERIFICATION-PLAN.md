# Verification ownership and acceptance mapping

The table maps full requirement ownership, not a claim that every counterexample has passed. Current executable tests live in Tests/InvarTests and Tools/verify-*.py. Rich Explorer extension acceptance is owned by separate Explorer work before the Invar adapter can be verified. Imported acceptance wording remains in [Invar-SPEC.md](Requirements/Invar-SPEC.md); this document owns the mapping to design boundaries and the minimum counterexamples that must falsify an incorrect implementation.

| Acceptance IDs | Acceptance owner | Required behavioral counterexample / evidence |
|---|---|---|
| INV-001..003 | VerificationExplorerTests / PackageIntegrationTests | Real local products compose without reverse dependencies; simultaneous Invar/Explorer/MCP clients share the same source daemon and verification coordinator |
| INV-004..007 | VerificationDiscoveryTests / VerificationExplorerTests | Cross-page facts, incomplete coverage and cycles with/without explicit policy; pattern evidence cannot become native failure |
| INV-008..010 | VerificationCoreTests / VerificationDiscoveryTests | Missing/unapproved/self-derived oracle, empty input, zero executed cases and unproved/false preconditions cannot certify the intended obligation |
| INV-011..012 | VerificationPlannerTests / VerificationBackendTests | Missing capability and unsupported semantics block before execution; no name-derived FormalIR or hand-written semantic fallback |
| INV-013..015 | VerificationRuntimeTests / VerificationExplorerTests | Edits/context/lock changes mid-capture, truncated preview, expired input lease, sandbox escape and unknown build reads cannot create an apparently immutable input |
| INV-016..018 | VerificationBackendTests | Actual pinned finite TLC/Lean positive/negative/bound runs, translation UNVALIDATED and tampered artifacts/admitted/custom-axiom rejection; quantified mode additionally tests true/wrong/unproved properties with audited kernel output |
| INV-019..021 | VerificationCoreTests / VerificationBackendTests / VerificationPlannerTests | Spurious model witness, missing native replay and circular assume-guarantee dependencies are not a source/system proof |
| INV-022..025 | VerificationBackendTests | Real failure across two native modules; explicit real fuzz harness/profile; original and minimized input reproduce the same oracle violation; budget completion alone is not safety |
| INV-026..029 | VerificationRuntimeTests / VerificationBackendTests | Tool versus target crash, full output pipes, forced timeout/cancel, disk/memory/process caps and refused isolation; measure complete reap/cleanup and no silent host fallback |
| INV-030..035 | VerificationPlannerTests / VerificationRuntimeTests / VerificationExplorerTests | Mutate every source/context/property/tool/runtime/harness dependency, unknown call graph, old completion, unchanged full closure reuse, self-annotation events and multiple observers |
| INV-036..038 | VerificationExplorerTests | Real rich extension rendering, duplicate/stale ActionIntent and deletion/ambiguous rename. Requires separately implemented extension SDK |
| INV-039..040 | VerificationCoreTests / InvarCLITests | Mandatory unexecuted obligation, expired suppression or hidden exclusion cannot yield CI success |
| INV-041..044 | PackageIntegrationTests / InvarCLITests | Conditional/arithmetic/order mutations, disagreeing methods, parser failure hiding a finding and fixed-input CLI/GUI/MCP report equivalence |
| INV-045..047 | SemanticInteractionIntegrationTests / VerificationBackendTests | V5 real semantics for multiple Actors, bad/correct interleavings, cancellation/failure/retry/fairness; missing profile stays BLOCKED with visible coverage |
| INV-048 | VerificationStoreTests / PackageIntegrationTests | Fresh execution and valid cached association agree on property/domain/scope/inputs/assessment while original provenance stays immutable |

Cross-cutting native Store tests cover actual SQLite linkage, commit/rollback, kill-before/after-commit, explicit incompatible-format refusal, corrupt/missing blobs and retention under active readers. Runtime parallelism tests must instrument actual simultaneous backend entries, predecessor completion order, peak aggregate resources and complete wall time. Swift Testing suites sharing any resource must use the same actor/Mutex exclusion across suites; per-suite serialization alone is insufficient.

## Verification sequence

Use a bounded red counterexample for each changed invariant, implement at its owning boundary, and run focused green tests. After the contracts and implementation converge, run affected targets/package checks once, then one integrated task check. Every test process has an explicit timeout and owned-process cleanup. Reuse unchanged prerequisite evidence; do not count repeated identical runs as additional coverage.

Actual formal proof success requires real pinned tool execution and audit logs. A fake backend tests orchestration/failure contracts only. A build, parser scan, schema or document link check establishes no backend correctness. Product runtime installation and native/Fuzz execution authority are separate from repository build/test dependencies.

## Current evidence and uncovered acceptance

DomainTests/PlanContractTests cover policy witnesses, incomplete/empty scope, status domains, canonical identities, unsafe plans and oracle validation. SchedulerTests/DurableCoordinatorTests cover actual async overlap, ordering, admission, cancellation, separate shared execution interests and stale completion. ReplayTests cover preserved unreproduced/inconclusive history and store reopen.

The actual CLI scripts cover pinned TLC/Lean, native module contracts, sandbox denials, native oracle/trap/crash distinctions, deterministic fuzz shrinking/replay, MCP protocol authority and watch edit/reconnect behavior. Their exact commands/results are recorded in PROGRESS.md. These are partial evidence for the corresponding acceptance rows, not blanket passes for all IDs in a range.

The daemon SDK tests now cover actual Action delivery/cancellation/restart, shared CLI/MCP view identity, retained-store admission/pruning and source/watch lifetime. Their exact evidence stays scoped to the exercised paths. Uncovered acceptance remains open: separate GUI renderer behavior, V5 Actor/multi-module semantic correspondence, general spurious-model-witness lifting and suppression expiry. No implemented adapter invents these capabilities. V0–V4 and the full requested system are not declared complete.

## Daemon and structured SDK revision

The new ID/IC/IE/IV/IS acceptance cases are owned by [SDK transition](SDK-TRANSITION.md), and Formal FE cases by [Formal transition](https://github.com/1amageek/swift-formal/blob/main/Documentation/SDK-TRANSITION.md). They are not counted as passes of the earlier INV mapping. Schema1-specific ticket/service tests are removed; actual replacement owner/process tests cover the new runtime. No migration or backward-compatible runtime is provided.
