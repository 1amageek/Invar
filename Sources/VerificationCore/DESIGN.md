# VerificationCore

## Purpose and Scope
Immutable request, identity, change and evidence meaning; public narrow ports and pure assessment. Parent: [Invar](../../DESIGN.md). Target contracts are authoritative for new implementation; current behavior evidence remains in PROGRESS.md. Children are indexed below.

## Responsibilities and Boundaries
Immutable request, identity, change and evidence meaning; public narrow ports and pure assessment. No concrete client/store/backend or Formal/Explorer dependency. New change/evidence schema 2 supersedes raw inline report and ticket-only domain contracts. Domain retains basic input/job/value primitives; Changes and Evidence own their detailed meanings.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Invar](../../DESIGN.md) | parent | System composition | Module boundary | Target design is not implementation evidence |
| [Domain](Domain/DESIGN.md) | child | Owned component contract | Domain | See implementation/deletion gate |
| [Assessment](Assessment/DESIGN.md) | child | Owned component contract | Assessment | See implementation/deletion gate |
| [Changes](Changes/DESIGN.md) | child | Owned component contract | Changes | See implementation/deletion gate |
| [Evidence](Evidence/DESIGN.md) | child | Owned component contract | Evidence | See implementation/deletion gate |
| [VerificationClient](../VerificationClient/DESIGN.md) | used by | Domain client ports | Direct module boundary | Recheck at SDK cutover |
| [VerificationRuntime](../VerificationRuntime/DESIGN.md) | used by | Operation and execution ports | Direct module boundary | Recheck at SDK cutover |
| [VerificationStore](../VerificationStore/DESIGN.md) | used by | Immutable records and repository contracts | Direct module boundary | Recheck at SDK cutover |
| [VerificationBackends](../VerificationBackends/DESIGN.md) | used by | Job/evidence contracts | Direct module boundary | Recheck at SDK cutover |

## Architecture
```text
Composition -> VerificationCore public protocols -> owned components -> immutable result / typed failure
```

## Contracts and Invariants
No concrete client/store/backend or Formal/Explorer dependency. New change/evidence schema 2 supersedes raw inline report and ticket-only domain contracts. Domain retains basic input/job/value primitives; Changes and Evidence own their detailed meanings. Detailed meanings and APIs have one owner in the child designs. [SDK transition](../../Documentation/SDK-TRANSITION.md) owns replacement/removal sequencing; no backward-compatibility path is required.

## State, Ownership, and Lifecycle
Immutable Sendable values cross boundaries. Component actors/explicit resource owners handle mutation, subscriptions, process/file/database lifetimes and awaited shutdown. No WASM/Embedded state branch is introduced; the host profile remains macOS 27 arm64.

## Failure, Concurrency, and Constraints
Bound work with persisted policy and negotiated capabilities. Unknown/unsupported semantics, failed persistence and incomplete cleanup remain explicit. Do not install runtimes during verification.

## Verification and Change Impact
[Verification ownership](../../Documentation/VERIFICATION-PLAN.md) maps existing evidence and new ID/IC/IE/IV/IS acceptance. Recheck parent/direct consumers when a child contract changes. New products/ports are not advertised before their implementation and behavioral gates pass.
