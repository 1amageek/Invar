# VerificationBackends.Artifacts

## Purpose and Scope
Own private backend artifact staging. Parent: [Backends](../DESIGN.md). No children.

## Responsibilities and Boundaries
Produce digest-bound files for coordinator adoption. No Store transactions, retention, publication or logical verdicts. Native/Formal consumers provide exact bytes or closed immutable bundle references.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Backends](../DESIGN.md) | parent | Worker lifetime | Owns staging root | Root must be private |
| [Persistence](../../VerificationStore/Persistence/DESIGN.md) | used by | Verified artifact adoption | Publishes references | Adoption precedes terminal commit |
| [Evidence](../../VerificationCore/Evidence/DESIGN.md) | depends on | Artifact references | Immutable meaning | No inline reports |

## Architecture
```text
bounded JSON / closed bundle -> digest-named private staging -> Store verifies and adopts -> evidence reference
```

## Contracts and Invariants
JSON is fsynced before becoming a staged object. Closed Formal SQLite files are hard-linked from immutable owned bundles on the same filesystem, preserving zero-copy ownership transfer and original bundle readers. API owners never open published artifacts for writing. Cross-filesystem transfer fails explicitly; no implicit copy changes the resource contract. The coordinator verifies bytes and manifest before adopting an object. A staged object is not a committed reference.

## State, Ownership, and Lifecycle
Invocation-local file handles; the worker owns staging until the coordinator adopts it. Cancellation/failure retains owned forensic work under Store reservation/recovery policy. No shared mutable cache.

## Failure, Concurrency, and Constraints
Byte limits come from the admitted attempt; all references use normalized digest-only object names. Hash/size conflict and incomplete transfer fail explicitly.

## Verification and Change Impact
Artifact adoption tests cover missing/tampered bytes, identical/conflicting objects and publication ordering. Recheck Store, Core and Formal/Native consumers when staging layout changes.
