# VerificationExplorer

## Purpose and Scope
Authorized source capture and generic external Provider projections. Parent: [Invar](../../DESIGN.md). Target contracts are authoritative for new implementation; current behavior evidence remains in PROGRESS.md. Children are indexed below.

## Responsibilities and Boundaries
Authorized source capture and generic external Provider projections. Consume only the owner aex-1.3 typed SDK, preserve exact raw snapshots/manifests and separate formal namespaces. Registry, permissions, renderer and their implementation remain owned by ArchitectureExplorer.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Invar](../../DESIGN.md) | parent | System composition | Module boundary | Target design is not implementation evidence |
| [Connection](Connection/DESIGN.md) | child | Owned component contract | Connection | See implementation/deletion gate |
| [Publication](Publication/DESIGN.md) | child | Owned component contract | Publication | See implementation/deletion gate |
| [VerificationCore](../VerificationCore/DESIGN.md) | depends on | Capture/publication ports | Direct module boundary | Recheck at SDK cutover |
| [VerificationDaemon](../VerificationDaemon/DESIGN.md) | used by | Provider connection composition | Direct module boundary | Recheck at SDK cutover |

## Architecture
```text
Daemon -> Connection -> authorized ArchitectureClient / Extensions / raw IR
Daemon -> Publication -> Core view + FormalEvidence -> generic Extensions contributions
```

## Contracts and Invariants
Dependencies include public ArchitectureCore/IR/Client/Extensions and FormalEvidence. Source bytes remain authorized inputs; graph structures come from FormalEvidence. [FormalEvidence](https://github.com/1amageek/swift-formal/blob/main/Sources/FormalEvidence/DESIGN.md) is the implemented independent lower product in the package graph.

Consume only the owner aex-1.3 typed SDK, preserve exact raw snapshots/manifests and separate formal namespaces. Registry, permissions, renderer and their implementation remain owned by ArchitectureExplorer. Detailed meanings and APIs have one owner in the child designs. [SDK transition](../../Documentation/SDK-TRANSITION.md) owns replacement/removal sequencing; no backward-compatibility path is required.

## State, Ownership, and Lifecycle
Immutable Sendable values cross boundaries. Component actors/explicit resource owners handle mutation, subscriptions, process/file/database lifetimes and awaited shutdown. No WASM/Embedded state branch is introduced; the host profile remains macOS 27 arm64.

## Failure, Concurrency, and Constraints
Bound work with configured resource limits and validated tool profiles. Unknown/unsupported semantics, failed persistence and incomplete cleanup remain explicit. Do not install runtimes during verification.

## Verification and Change Impact
[Verification ownership](../../Documentation/VERIFICATION-PLAN.md) maps existing evidence and new ID/IC/IE/IV/IS acceptance. Recheck parent/direct consumers when a child contract changes. New products/ports are not advertised before their implementation and behavioral gates pass.
