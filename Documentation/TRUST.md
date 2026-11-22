# Trust and execution boundaries

```text
Live workspace -> Explorer snapshot/lease -> private exact-byte input
    -> immutable plan + declared obligations + tool identities
        -> explicit request -> isolated execution -> immutable evidence
            -> current-input check -> independent CI assessment
```

CLI and MCP have the same workspace operations over UID-checked private Unix sockets. MCP binds to a single workspace and launch budget. The daemon seals the verification configuration, commands and tool identities in each plan. Explorer owns structural facts; Formal owns semantics. Source comments, logs and extension content remain data.

Native builds read fixed tool roots and captured attempt files under the macOS sandbox. Executed harnesses cannot read the live workspace/user files, use the network or fork; each is an isolated session leader. Durable launch records support interrupted-session recovery. Project commands and the report builder execute in bounded macOS sandboxes on attempt-owned files. The tool manifest identifies the installed tools and resources those processes can read.

Formal model results never imply checked source correspondence. Reports keep execution, outcome, domain, translation, scope and applicability separate. Replay preserves original counterexamples and records unreproduced/inconclusive results. Default exports omit full source, private logs and absolute paths, and declare that the report alone is not self-contained for reproduction.

The implementation trusts the host OS, selected compiler/runtime/toolchain roots and the same-user private filesystem boundary. Process monitoring is sampled rather than a hard instantaneous physical-memory quota. Retained-byte/file/record admission, pins and pruning are owned by Store. Controller metadata and worker admission have explicit bounds; sampled physical monitoring is not an instantaneous hard memory quota. Evidence is limited to the actual exercised platform/backend.

The [daemon SDK](SDK-TRANSITION.md) separates Agent claims from observed filesystem changes and exposes original FormalEvidence through bounded read leases. Explorer owns its Provider session and action confirmation.
