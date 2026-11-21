# InvarConnectionFailure fixture

## Purpose and Scope
Own a distinct Provider executable for post-registration credential publication failure. Parent: [fixture package](../../DESIGN.md). No children.

## Responsibilities and Boundaries
Use actual ExplorerProviderConnection against the owned unmodified Explorer host; no source indexing or fake authentication.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Connection](../../../../../Sources/VerificationExplorer/Connection/DESIGN.md) | depends on | Explicit Provider ownership/cleanup | Failure-path check | Different binary from host is required for ordinary Provider authorization |

## Architecture
```text
Owned Explorer host <-> distinct Provider process -> failing private credential destination
```

## Contracts and Invariants
The external driver approves only this process. Registration is real; local credential publication fails after initialization because its target is a directory. Shutdown must leave the host registration disconnected.

## Verification and Change Impact
Tools/verify-provider-connection-cleanup.py checks the actual host's registration after the Provider exits. This certifies one ordinary-peer failure path, not all transport/disconnect failures.
