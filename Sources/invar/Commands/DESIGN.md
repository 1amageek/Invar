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
CommandOptions accepts exact protocol-2 client commands, startup capability ceiling, private client profile, explicit request key and optional bounded observation. ClientConnection reads the private pinned endpoint and connects LocalClientProfile outside the workspace/daemon Store. Ordinary commands never open Store, capture files, compile, plan locally, launch a legacy service or infer permission from a Boolean. Mutating commands return durable receipts; --wait observes the original operation only. CI composes admitted plan and verification requests using distinct suffixes of the explicit original key, then returns the daemon summary/exit assessment. Client cancellation/exit closes observation without cancelling durable work or watches.

The workspace launcher composes the Explorer executable pair and Invar daemon through their real entry points. CLI-owned watch loops and observer tickets are removed. Explorer publication occurs through the daemon automatically. Private source/records/formal reads require explicit startup sourceValues; Native execution additionally requires the actual host grant and matching requested capability. Capabilities are fixed per client profile, and a different profile is needed for a different ceiling/engine.

The offline `invar map` entry point delegates explicit source/configuration inputs to [InvarMap](../../InvarMap/DESIGN.md). It never opens a daemon store or admits a verification operation.

### Workspace startup

An explicit `--workspace` chooses that directory. Otherwise resolve the physical current directory and walk parents to the nearest Git checkout or worktree marker. Outside a checkout, require an explicit `--workspace`. CLI and MCP resolve before locating an endpoint; one process binds one workspace. `capabilities` and private worker operations remain independent of Git discovery.

`invar` starts or reuses the Explorer index daemon and Invar daemon, prints the absolute workspace and Invar readiness, then opens Explorer. The foreground Explorer command owns its browser server; verification and indexing daemons survive its exit. A fresh workspace can be shown during `approvalRequired`. An explicit `--policy` supplies an existing reviewed policy to a new daemon; updating a running policy uses `invar daemon approve`. The launcher selects the matching Explorer CLI and Web pair from the host installation. A headless MCP startup uses the same workspace and can start its index daemon without opening a browser.

`invar mcp` reuses the existing daemon or recovers an already configured workspace on demand. Recovery with no persisted policy or after explicit stop is rejected before the MCP handshake. Host and Provider approval checks are in force for every execution. Only explicit `invar` startup clears a stop latch. `invar status` and `invar stop` use private administration and never bootstrap a replacement. Simultaneous launches converge on the authenticated workspace owner.
