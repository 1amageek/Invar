# VerificationDiscovery

## Purpose and Scope
Deterministic architecture policy evaluation, observed change differences and conservative impact analysis. Parent: [Invar](../../DESIGN.md). Target contracts are authoritative for new implementation; current behavior evidence remains in PROGRESS.md. Children are indexed below.

## Responsibilities and Boundaries
Deterministic architecture policy evaluation, observed change differences and conservative impact analysis. Consume raw pinned records/bytes from the shared Explorer owner. Do not reparse source to invent symbol correspondence, author identity or temporal/formal semantics.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Invar](../../DESIGN.md) | parent | System composition | Module boundary | Target design is not implementation evidence |
| [Rules](Rules/DESIGN.md) | child | Owned component contract | Rules | See implementation/deletion gate |
| [Changes](Changes/DESIGN.md) | child | Owned component contract | Changes | See implementation/deletion gate |
| [VerificationCore](../VerificationCore/DESIGN.md) | depends on | Inventory, changes and coverage | Direct module boundary | Recheck at SDK cutover |
| [VerificationDaemon](../VerificationDaemon/DESIGN.md) | used by | Discovery/change analysis composition | Direct module boundary | Recheck at SDK cutover |

## Architecture
```text
Composition -> VerificationDiscovery public protocols -> owned components -> immutable result / typed failure
```

## Contracts and Invariants
Consume raw pinned records/bytes from the shared Explorer owner. Do not reparse source to invent symbol correspondence, author identity or temporal/formal semantics. Detailed meanings and APIs have one owner in the child designs. [SDK transition](../../Documentation/SDK-TRANSITION.md) owns replacement/removal sequencing; no backward-compatibility path is required.

## State, Ownership, and Lifecycle
Immutable Sendable values cross boundaries. Component actors/explicit resource owners handle mutation, subscriptions, process/file/database lifetimes and awaited shutdown. No WASM/Embedded state branch is introduced; the host profile remains macOS 27 arm64.

## Failure, Concurrency, and Constraints
Bound work with persisted policy and negotiated capabilities. Unknown/unsupported semantics, failed persistence and incomplete cleanup remain explicit. Do not install runtimes during verification.

## Verification and Change Impact
[Verification ownership](../../Documentation/VERIFICATION-PLAN.md) maps existing evidence and new ID/IC/IE/IV/IS acceptance. Recheck parent/direct consumers when a child contract changes. New products/ports are not advertised before their implementation and behavioral gates pass.
