# VerificationDiscovery.Changes

## Purpose and Scope
Implemented component contract. Own exact observed difference and conservative impact analysis. Parent: [Discovery](../DESIGN.md). No children.

## Responsibilities and Boundaries
Consume two pinned inventories/original input manifests and Agent claims. Produce ObservedDelta/SubjectCorrespondence/impact coverage. No independent source index, semantic parser, edit broker or verification result.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Discovery](../DESIGN.md) | parent | Deterministic observations | Component owner | Current rules remain distinct |
| [Changes](../../VerificationCore/Changes/DESIGN.md) | depends on | Delta/attribution meaning | Immutable records | Claimed authorship remains a claim |
| [Explorer connection](../../VerificationExplorer/Connection/DESIGN.md) | depends on | Raw pinned facts and exact inputs | Structure authority | GraphView projection is insufficient |

## Architecture
```text
before/after bytes + raw records + context -> exact file/record delta
  -> verified subject correspondences + explicit ambiguity
  -> dependency impact closure + unresolved/excluded boundaries
```

## Contracts and Invariants
`ChangeAnalyzing.analyze(ChangeAnalysisRequest) -> ChangeAnalysis` is a pure bounded operation, executed in a worker when size requires it. Byte diff identifies actual hunks; syntax entities/facts come only from Explorer's original records. Names never establish continuity. A unique exact-content path move may be labeled content-move with its basis; ambiguous duplicates remain additions/deletions with an unresolved correspondence.

Impact traverses requested typed relations with actual provenance. Unknown calls/context/alias resolution cause conservative expansion up to the declared enclosing scope and explicit unknown boundaries. Call edges do not imply temporal order, happens-before or Actor semantics. Contract/oracle changes are explicit delta entries; weakening an oracle never resolves an old failure silently.

Agent claims are compared with observed hunks and overlapping registered revisions. Unclaimed changes remain external/unknown. No file timestamp or matching patch hash proves exclusive authorship.

## State, Ownership, and Lifecycle
Invocation-local views retain immutable source owners; returned records contain references/ranges rather than copied file bodies. Runtime owns capture lifetime; Store retains both ends of a sealed change.

## Failure, Concurrency, and Constraints
Bound input records, diff bytes/hunks, traversal depth/visits/time and output bytes. Budget exhaustion returns incomplete coverage with boundaries or typed failure, never a complete empty impact set. No live disk read supplements a missing historical file.

## Verification and Change Impact
Planned **IC-01..05** use real Explorer snapshots plus independent byte-diff fixtures for renames, deletion, shifted offsets, two overlapping Agents, user edits and unknown relations. A small reference traversal must match the indexed result. Recheck Changes, Watching, Planner and projections.

### Byte and impact implementation profile
The initial differ emits one enclosing exact hunk per changed file using common byte prefix/suffix. For valid UTF-8 it expands both ends to code-point boundaries and derives 1-based line positions; binary deltas retain exact byte regions with unavailable line positions. This is an exact enclosing observation, not a minimal edit script. A path move is linked only when the digest is unique across both complete before/after manifests; duplicate content remains ambiguous. Raw entity/fact identities and record bytes are compared directly. Reverse relation traversal computes dependents; unknown project closure/coverage expands impact to the entire captured enclosing scope with explicit uncertainty. Caller-supplied budgets bound files, bytes, records, visits and result bytes. No source body is embedded in the returned delta.
