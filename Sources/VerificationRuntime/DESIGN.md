# VerificationRuntime

## Purpose and Scope
Daemon-owned coordination, resource admission, watches and process lifetime. Parent: [Invar](../../DESIGN.md). Target contracts are authoritative for new implementation; current behavior evidence remains in PROGRESS.md. Children are indexed below.

## Responsibilities and Boundaries
Daemon-owned coordination, resource admission, watches and process lifetime. Use injected Core ports. Shared jobs span admitted plans without a whole-plan tail; watches and accepted run interests outlive frontend sessions. No concrete Store, Backend or Explorer import is needed.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Invar](../../DESIGN.md) | parent | System composition | Module boundary | Target design is not implementation evidence |
| [Coordination](Coordination/DESIGN.md) | child | Owned component contract | Coordination | See implementation/deletion gate |
| [Scheduling](Scheduling/DESIGN.md) | child | Owned component contract | Scheduling | See implementation/deletion gate |
| [Watching](Watching/DESIGN.md) | child | Owned component contract | Watching | See implementation/deletion gate |
| [Execution](Execution/DESIGN.md) | child | Owned component contract | Execution | See implementation/deletion gate |
| [VerificationCore](../VerificationCore/DESIGN.md) | depends on | Domain ports and records | Direct module boundary | Recheck at SDK cutover |
| [VerificationDaemon](../VerificationDaemon/DESIGN.md) | used by | Coordination/admission/monitoring | Direct module boundary | Recheck at SDK cutover |

## Architecture
```text
Composition -> VerificationRuntime public protocols -> owned components -> immutable result / typed failure
```

## Contracts and Invariants
Use injected Core ports. Shared jobs span admitted plans without a whole-plan tail; watches and accepted run interests outlive frontend sessions. No concrete Store, Backend or Explorer import is needed. Detailed meanings and APIs have one owner in the child designs. [SDK transition](../../Documentation/SDK-TRANSITION.md) owns replacement/removal sequencing; no backward-compatibility path is required.

## State, Ownership, and Lifecycle
Immutable Sendable values cross boundaries. Component actors/explicit resource owners handle mutation, subscriptions, process/file/database lifetimes and awaited shutdown. No WASM/Embedded state branch is introduced; the host profile remains macOS 27 arm64.

## Failure, Concurrency, and Constraints
Bound work with persisted policy and negotiated capabilities. Unknown/unsupported semantics, failed persistence and incomplete cleanup remain explicit. Do not install runtimes during verification.

## Verification and Change Impact
[Verification ownership](../../Documentation/VERIFICATION-PLAN.md) maps existing evidence and new ID/IC/IE/IV/IS acceptance. Recheck parent/direct consumers when a child contract changes. New products/ports are not advertised before their implementation and behavioral gates pass.
