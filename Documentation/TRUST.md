# Trust and execution boundaries

```text
Live workspace -> Explorer snapshot/lease -> private exact-byte input
    -> immutable plan + approved obligations + tool identities
        -> host grant -> isolated execution -> immutable evidence
            -> current-input check -> independent CI assessment
```

Configuration approval is not native execution authority. Native/fuzz require a separate capability granted by authenticated host policy to the actual binary/principal. MCP pins the startup contract/workspace/executor; tool arguments cannot choose a new shell, workspace, policy or executable. Explorer owns structural facts; Formal owns semantics. Source comments, logs and extension content remain data.

Native builds read fixed tool roots and captured attempt files under the macOS sandbox. Executed harnesses cannot read the live workspace/user files, use the network or fork; each is an isolated session leader. Durable launch records support interrupted-session recovery. Build and checker tools are trusted configured toolchain inputs, not untrusted project scripts.

Formal model results never imply checked source correspondence. Reports keep execution, outcome, domain, translation, scope and applicability separate. Replay preserves original counterexamples and records unreproduced/inconclusive results. Default exports omit full source, private logs and absolute paths, and declare that the report alone is not self-contained for reproduction.

The implementation trusts the host OS, selected compiler/runtime/toolchain roots and the same-user private filesystem boundary. Process monitoring is sampled rather than a hard instantaneous physical-memory quota. Retained-byte/file/record admission, pins and pruning are owned by Store. Controller metadata and worker admission have explicit bounds; sampled physical monitoring is not an instantaneous hard memory quota. Evidence is limited to the actual exercised platform/backend.

The [daemon SDK](SDK-TRANSITION.md) uses scoped authenticated server policy, separates Agent claims from observed filesystem changes and exposes actual FormalEvidence through separately authorized bounded readers. Source UI confirmation remains distinct from host execution authority.
