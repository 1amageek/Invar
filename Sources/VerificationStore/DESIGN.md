# VerificationStore

## Purpose and Scope
Single-daemon durable operations, immutable inputs/evidence, common views and bounded retention. Parent: [Invar](../../DESIGN.md). Target contracts are authoritative for new implementation; current behavior evidence remains in PROGRESS.md. Children are indexed below.

## Responsibilities and Boundaries
Single-daemon durable operations, immutable inputs/evidence, common views and bounded retention. Store schema 2 has one writer and transactional receipts/operation creation, pins/quotas and an outbox. Frontends never open live SQLite. No legacy store migration/reader is part of the target runtime.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Invar](../../DESIGN.md) | parent | System composition | Module boundary | Target design is not implementation evidence |
| [Persistence](Persistence/DESIGN.md) | child | Owned component contract | Persistence | See implementation/deletion gate |
| [VerificationCore](../VerificationCore/DESIGN.md) | depends on | Immutable records and narrow repository ports | Direct module boundary | Recheck at SDK cutover |
| [CInvarSQLite](../CInvarSQLite/DESIGN.md) | depends on | Native SQLite linkage | Direct module boundary | Recheck at SDK cutover |
| [VerificationDaemon](../VerificationDaemon/DESIGN.md) | used by | Durable writer composition | Direct module boundary | Recheck at SDK cutover |

## Architecture
```text
Composition -> VerificationStore public protocols -> owned components -> immutable result / typed failure
```

## Contracts and Invariants
Store schema 2 has one writer and transactional receipts/operation creation, pins/quotas and an outbox. Frontends never open live SQLite. No legacy store migration/reader is part of the target runtime. Detailed meanings and APIs have one owner in the child designs. [SDK transition](../../Documentation/SDK-TRANSITION.md) owns replacement/removal sequencing; no backward-compatibility path is required.

## State, Ownership, and Lifecycle
Immutable Sendable values cross boundaries. Component actors/explicit resource owners handle mutation, subscriptions, process/file/database lifetimes and awaited shutdown. No WASM/Embedded state branch is introduced; the host profile remains macOS 27 arm64.

## Failure, Concurrency, and Constraints
Bound work with configured resource limits and validated tool profiles. Unknown/unsupported semantics, failed persistence and incomplete cleanup remain explicit. Do not install runtimes during verification.

## Verification and Change Impact
[Verification ownership](../../Documentation/VERIFICATION-PLAN.md) maps existing evidence and new ID/IC/IE/IV/IS acceptance. Recheck parent/direct consumers when a child contract changes. New products/ports are not advertised before their implementation and behavioral gates pass.
