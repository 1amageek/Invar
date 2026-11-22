# InvarExplorerHost

## Purpose and Scope
Own test host process and typed SDK client commands. Parent: [fixture package](../../DESIGN.md). No children.

## Responsibilities and Boundaries
Compose actual ArchitectureDaemon and expose bounded test-only CLI requests. No production verification logic, alternate parser or modified host authorization.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Fixture](../../DESIGN.md) | parent | Owned temporary process | Integration execution | Never target the user's workspace |

## Architecture
```text
serve -> actual SQLiteGraphStore + ArchitectureDaemon
rpc -> actual ArchitectureClient
request/query -> actual LocalVerificationClient
```

## Contracts and Invariants
Commands return actual SDK values. Ordinary client invocations connect through the same user’s private workspace socket. Host read/mutation calls execute from the actual pinned host binary.

## State, Ownership, and Lifecycle
Serve owns Store/daemon shutdown. Client commands close their local observations. The driver owns process termination and temporary filesystem cleanup.

## Failure, Concurrency, and Constraints
Arguments and JSON are bounded. Errors are machine-readable and nonzero. Every driver subprocess and observation has a deadline.

## Verification and Change Impact
The enclosing integration driver compares exact record/view identities and tests revoked permissions, fixed source leases and recovery behavior as applicable. Public SDK changes require rebuilding this helper in its own build directory.
