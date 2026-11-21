# invar

## Purpose and Scope
Thin executable entry for client commands, MCP relay, daemon serve and private workers. Parent: [Invar](../../DESIGN.md). Target contracts are authoritative for new implementation; current behavior evidence remains in PROGRESS.md. Children are indexed below.

## Responsibilities and Boundaries
Thin executable entry for client commands, MCP relay, daemon serve and private workers. CLI/MCP delegate to VerificationClient. Daemon/worker entries delegate to VerificationDaemon. Executable-owned Watching/WorkspaceService and direct Store/planning paths have been removed. Public daemon residency is independent of execution authority. Daemon and worker identity use the running executable's resolved bundle URL so a PATH invocation or Mint symlink selects the same engine and adjacent resources.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Invar](../../DESIGN.md) | parent | System composition | Module boundary | Target design is not implementation evidence |
| [Commands](Commands/DESIGN.md) | child | Owned component contract | Commands | See implementation/deletion gate |
| [MCP](MCP/DESIGN.md) | child | Owned component contract | MCP | See implementation/deletion gate |
| [VerificationClient](../VerificationClient/DESIGN.md) | depends on | Client workflow | Direct module boundary | Recheck at SDK cutover |
| [VerificationDaemon](../VerificationDaemon/DESIGN.md) | depends on | Daemon and private worker entries | Direct module boundary | Recheck at SDK cutover |

## Architecture
```text
Composition -> invar public protocols -> owned components -> immutable result / typed failure
```

## Contracts and Invariants
CLI/MCP delegate to VerificationClient. Daemon/worker entries delegate to VerificationDaemon. Executable-owned Watching/WorkspaceService and direct Store/planning paths have been removed. Public daemon residency is independent of execution authority. Detailed meanings and APIs have one owner in the child designs. [SDK transition](../../Documentation/SDK-TRANSITION.md) owns replacement/removal sequencing; no backward-compatibility path is required.

## State, Ownership, and Lifecycle
Immutable Sendable values cross boundaries. Component actors/explicit resource owners handle mutation, subscriptions, process/file/database lifetimes and awaited shutdown. No WASM/Embedded state branch is introduced; the host profile remains macOS 27 arm64.

## Failure, Concurrency, and Constraints
Bound work with persisted policy and negotiated capabilities. Unknown/unsupported semantics, failed persistence and incomplete cleanup remain explicit. Do not install runtimes during verification.

## Verification and Change Impact
[Verification ownership](../../Documentation/VERIFICATION-PLAN.md) maps existing evidence and new ID/IC/IE/IV/IS acceptance. Recheck parent/direct consumers when a child contract changes. New products/ports are not advertised before their implementation and behavioral gates pass.
