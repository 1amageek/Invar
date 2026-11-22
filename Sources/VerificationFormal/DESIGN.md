# VerificationFormal

## Purpose and Scope
Own typed Invar query/lease contracts that expose the independently owned FormalEvidence SDK. Parent: [Invar](../../DESIGN.md). Child: [Queries](Queries/DESIGN.md).

## Responsibilities and Boundaries
Bind a private Invar evidence record to bounded FormalEvidence reads without duplicating formal graph, trace, value or origin models. No Store, compiler, verifier, transport or SQLite owner is implemented here.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Invar](../../DESIGN.md) | parent | Public SDK boundaries | Data-only bridge | Core remains independent of Formal |
| [FormalEvidence](https://github.com/1amageek/swift-formal/blob/main/Sources/FormalEvidence/DESIGN.md) | depends on | Read models/protocols | Formal meaning owner | Preserve exact values and independent axes |
| [Client Formal](../VerificationClient/Formal/DESIGN.md) | used by | Typed remote query | Client reader implementation | No local file fallback |
| [Daemon FormalQueries](../VerificationDaemon/FormalQueries/DESIGN.md) | used by | Lease and local query | Server reader owner | Exact bundle and bounded pages |

## Architecture
```text
Invar evidence ID + Formal bundle reference -> typed read lease
  -> original FormalEvidence query/result types
```

## Contracts and Invariants
An opened lease binds its original evidence, bundle digest, daemon epoch and expiry. It is presentation/read state, not verification evidence. FormalEvidence remains the sole semantic owner of graph/value/origin records. Ordinary Core/client APIs do not acquire compiler or verifier dependencies.

## Verification and Change Impact
Actual server/client tests validate correct bundle ownership, principal/session isolation, page identity, bounded open counts, expiry/close, retention pins and private-value access. Root integration must use actual tool-produced bundles, not a graph fixture as proof of extraction.
