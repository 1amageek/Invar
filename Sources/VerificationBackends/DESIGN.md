# VerificationBackends

## Purpose and Scope
Method-specific policy/formal/native/fuzz execution and structured evidence adaptation. Parent: [Invar](../../DESIGN.md). Target contracts are authoritative for new implementation; current behavior evidence remains in PROGRESS.md. Children are indexed below.

## Responsibilities and Boundaries
Method-specific policy/formal/native/fuzz execution and structured evidence adaptation. Preserve exact captured inputs, independent declared oracles, scope/translation and isolation. Formal adapters consume the new FormalEvidence SDK at cutover; no Base64 report is the graph/claim authority.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Invar](../../DESIGN.md) | parent | System composition | Module boundary | Target design is not implementation evidence |
| [Static](Static/DESIGN.md) | child | Owned component contract | Static | See implementation/deletion gate |
| [Artifacts](Artifacts/DESIGN.md) | child | Owned staging | Artifact transfer | Verify adoption before commit |
| [Formal](Formal/DESIGN.md) | child | Owned component contract | Formal | See implementation/deletion gate |
| [Native](Native/DESIGN.md) | child | Owned component contract | Native | See implementation/deletion gate |
| [Project](Project/DESIGN.md) | child | Captured whole-project command | Receipt-bound three-phase report | Attempt-scoped sandbox and pinned tools |
| [VerificationCore](../VerificationCore/DESIGN.md) | depends on | Typed execution and evidence | Direct module boundary | Recheck at SDK cutover |
| [VerificationDaemon](../VerificationDaemon/DESIGN.md) | used by | Worker composition | Direct module boundary | Recheck at SDK cutover |

## Architecture
```text
Composition -> VerificationBackends public protocols -> owned components -> immutable result / typed failure
```

## Contracts and Invariants
Preserve exact captured inputs, independent declared oracles, scope/translation and isolation. Formal adapters consume the new FormalEvidence SDK at cutover; no Base64 report is the graph/claim authority. Detailed meanings and APIs have one owner in the child designs. [SDK transition](../../Documentation/SDK-TRANSITION.md) owns replacement/removal sequencing; no backward-compatibility path is required.

## State, Ownership, and Lifecycle
Immutable Sendable values cross boundaries. Component actors/explicit resource owners handle mutation, subscriptions, process/file/database lifetimes and awaited shutdown. No WASM/Embedded state branch is introduced; the host profile remains macOS 27 arm64.

## Failure, Concurrency, and Constraints
Bound work with configured resource limits and validated tool profiles. Unknown/unsupported semantics, failed persistence and incomplete cleanup remain explicit. Do not install runtimes during verification.

## Verification and Change Impact
[Verification ownership](../../Documentation/VERIFICATION-PLAN.md) maps existing evidence and new ID/IC/IE/IV/IS acceptance. Recheck parent/direct consumers when a child contract changes. New products/ports are not advertised before their implementation and behavioral gates pass.
