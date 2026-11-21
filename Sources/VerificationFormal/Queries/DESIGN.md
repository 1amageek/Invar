# VerificationFormal.Queries

## Purpose and Scope
Own typed remote formal read requests/results and read policy. Parent: [Formal bridge](../DESIGN.md). No children.

## Responsibilities and Boundaries
Represent admitted private reads and their original FormalEvidence result values. No verdict derivation or graph reconstruction.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Formal bridge](../DESIGN.md) | parent | Public contract | Types only | No persistence lifetime |

## Architecture
```text
open(evidence,bundle,budget) -> lease -> catalog/graph/trace/origins/document -> close
```

## Contracts and Invariants
Query/result cases are exact schema-2 protocol values. Handles are opaque, session/principal-bound and expire; explicit close is idempotent for an absent handle and cannot close another session's handle. Policy caps lower read budgets, concurrent handles and lease lifetime. Overflow or unavailable data is an explicit error, never an empty successful proof.

## Verification and Change Impact
Mutation tests reject forged reference/handle/result identities and unknown wire fields. Server/client behavioral tests own lifecycle and actual paged result round trips.
