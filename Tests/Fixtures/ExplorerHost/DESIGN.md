# Explorer Integration Host Fixture

## Purpose and Scope
Own the private real-process integration fixture for Invar and the unmodified ArchitectureExplorer public SDK. Parent: [Invar](../../../DESIGN.md). Child: [host executable](Sources/InvarExplorerHost/DESIGN.md).

## Responsibilities and Boundaries
Build a temporary host through the public ArchitectureDaemon composition API and exercise peer-bound Provider/Client paths. This is a test package, not a shipping product or a replacement source index.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Hosting](../../../Sources/VerificationDaemon/Hosting/DESIGN.md) | tests | Daemon lifecycle/IPC | Actual separate processes | Use only a unique temporary workspace |
| [Connection](../../../Sources/VerificationExplorer/Connection/DESIGN.md) | tests | Provider input leases | Actual owner SDK | Do not modify the owner or its running user instance |

## Architecture
```text
owned host process + actual ArchitectureService -> approved Invar Provider
owned host CLI -> authenticated Invar Client -> common committed records
```

## Contracts and Invariants
The host pins its own actual executable; only that helper can approve the test Provider. All state/processes are tied to the unique fixture workspace. Source files, source graph, approvals and protocol messages follow the real public implementations. No mock success or user UI/server state is used.

## Verification and Change Impact
The bounded integration driver owns setup, assertions and cleanup. Recheck the actual owner SDK when its fingerprint changes. This fixture establishes transport/source/record integration; it does not claim visual renderer correctness without separate renderer evidence.

Child: [distinct Provider failure executable](Sources/InvarConnectionFailure/DESIGN.md). It must have a different binary digest from the Explorer host so source disconnect uses the ordinary Provider authorization branch.

The optional --watch integration path detaches submitting SDK processes, checks quiet monitoring, edits actual source, kills/restarts the owned Invar daemon and stops the retained watch. It verifies fixed original principal lifetime and original run preservation on exact-scope reassociation, separately from expensive Formal tool checks.

Optional --actions exercises actual Source prepare/confirm, concrete SDK receipts, original-run publication adoption, cancellation and SIGKILL/no external restart with real TLC/Lean workers. --native owns a separate explicit toolchain/host-grant run for actual native modules, sandbox/oracle failures, fuzz shrinking and replay. It does not share a user server.
