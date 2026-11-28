# invar.Commands

## Purpose and Scope
Own CLI composition and machine-readable output. Parent: [module](../DESIGN.md). No children.

## Responsibilities and Boundaries
Validate arguments and file paths, connect VerificationClient and preserve typed exit/status distinctions. No source/comment/log becomes an execution instruction.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Public domain/module contracts | Component owner | Recheck direct consumers on changes |
| [Verification plan](../../../Documentation/VERIFICATION-PLAN.md) | coordinates with | Behavioral acceptance ownership | Test mapping | Mocks do not establish backend semantics |

## Architecture
```text
Validated input -> Commands -> immutable result or typed failure
```

## Contracts and Invariants
Implemented SDK revision. Commands use VerificationClient only for live workspace operations. Move source/config capture, tool inventory, plan building, Store writes and current assessment into daemon owners. Provide daemon start/serve/status/stop, change lifecycle, durable watch registration, run/replay/status and bounded evidence queries through the same typed operations. Offline export reading is explicitly offline; it is not a direct live-DB fallback.

Preserve exact input identity, separate execution/property/domain/translation/applicability, and propagate typed failures. Public API is protocol-based; concrete state does not escape its owner.

## State, Ownership, and Lifecycle
Invocation-local values or module-owned actors; no shared mutable global or target-specific synchronization. Active resource owners provide explicit shutdown/cleanup.

## Failure, Concurrency, and Constraints
Bound inputs and outputs according to the module contract. Cancellation/resource exhaustion is incomplete, never proof. External callbacks and I/O execute outside short Mutex scopes.

## Verification and Change Impact
Corresponding Invar test targets execute positive and negative behavior and invariant mutations. Changes recheck the parent module and its direct consumers; no completion claim comes from document structure.

The executable bridges SIGINT/SIGTERM through the existing ArchitectureCore signal boundary into cancellation of the invocation task. It awaits invocation cleanup before exiting 130. CLI observation detaches only that client; explicit cancellation controls its own durable demand. MCP shutdown stops and drains the SDK receiver and client observations; the daemon retains Store ownership.

[SDK transition](../../../Documentation/SDK-TRANSITION.md) owns current implementation facts, exact removal order and acceptance gates.

### Daemon SDK cutover
CommandOptions accepts the workspace and request parameters, including an explicit key and optional bounded observation. ClientConnection reads the private endpoint and connects LocalVerificationClient. CLI commands share the same daemon used by MCP.

The workspace launcher starts the bundled Explorer host and the Invar daemon through their own entry points. The daemon owns watches and publication. CLI reads can retrieve retained receipts, reports and formal evidence through the local client.

The offline `invar map` entry point delegates explicit source/configuration inputs to [InvarMap](../../InvarMap/DESIGN.md). It never opens a daemon store or admits a verification operation.

### Workspace startup

An explicit `--workspace` chooses that directory. Otherwise resolve the physical current directory and walk parents to the nearest Git checkout or worktree marker. Outside a checkout, require an explicit `--workspace`. CLI and MCP resolve before locating an endpoint; one process binds one workspace. `capabilities` and private worker operations remain independent of Git discovery.

`invar` starts or reuses the bundled Explorer index and the Invar daemon, prints the absolute workspace path and opens Explorer. Its foreground browser server is independent of the verification and indexing daemons.

`invar mcp` reuses the workspace daemon or starts it on demand. An explicit user stop persists until the next explicit start. Explorer owns Provider registration for its source and publication APIs.

### Verification tool setup

`invar setup` prepares selected verification profiles in a user-owned Invar tool directory before a plan captures its executables. The CLI emits the resolved paths and per-profile readiness as JSON. The Agent selects profiles from the reviewed verification work. A plain workspace open and a verification run have independent lifetimes and use their existing entry points.

Setup serializes changes to its tool directory across processes. Prebuilt archives are verified against pinned digests before extraction. The Formal SDK owns its default runtime inventory. Preparation preserves the project's Lean version selection and provides a separate offline TLC for project workflows. Prepared tools reside outside the repository and system PATH. A local Docker engine remains a host prerequisite for language image preparation, with an explicit readiness diagnostic when unavailable.

Repeated setup uses the same verified runtime and tool paths. Failed preparation reports the affected profile without accepting a partial profile as ready.
