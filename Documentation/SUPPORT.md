# Supported profile and limits

| Area | Implemented path | Evidence boundary |
|---|---|---|
| Host | Swift6.4.1 / macOS27 arm64 | No WASM/Embedded/GPU claim |
| Architecture | Original Explorer snapshot/lease and conservative policies | Unknown dependency/coverage stays visible |
| Formal | Actual pinned SANY/TLC/Lean, original rooted catalogs and ordered traces | generatedModel / UNVALIDATED; no general Actor semantics |
| Native/Fuzz | Captured module DAG, explicit harness/corpus/seed and checked shrinking | Existing explicit toolchain roots and sandboxed execution |
| Project | Captured command and independent report validation in an attempt sandbox | Tools use attempt-local temporary files and run without network listeners. TLC 1.7.4 starts an RMI listener. Use a checker compatible with the sandbox for project scripts. |
| Runtime | Persistent workspace daemon, cross-plan shared workers, fixed requests and daemon-owned watches | Accepted started/external work is never automatically restarted |
| Store | Schema2 immutable records, total retained-byte/file/record admission, reservations, pins and bounded pruning | Physical exhaustion is explicit failure/recoveryBlocked |
| CLI/MCP/SDK | Shared same-user workspace endpoint and durable operation IDs | Client exit does not cancel accepted work or watches |
| Explorer | Concrete SDK ledger Actions and original-generation structural publication | GUI rendering and private source mediation belong to Explorer |

The default view is the confirmed complete Explorer head; per-operation history and source uncertainty are independent. Optional unavailable extraction and incomplete execution cannot be promoted to proof. Sampled process resource monitoring is not an instantaneous hard physical quota. See [PROGRESS](../PROGRESS.md) for exact test/backend/platform evidence and [SDK transition](SDK-TRANSITION.md) for removed interfaces. The full original V0–V5 specification is not declared complete by this SDK task.
