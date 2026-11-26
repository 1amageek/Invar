# invar.MCP

## Purpose and Scope
Compose the user-selected local [Swift SDK](https://github.com/1amageek/swift-sdk/blob/main/DESIGN.md) into the Invar CLI. Parent: [invar](../DESIGN.md). No children.

## Responsibilities and Boundaries
The SDK owns protocol versions, codec, negotiation, stdio framing and request dispatch. Invar owns tool schemas, workspace binding, bounded projections and typed client requests. No second MCP implementation is introduced.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [invar](../DESIGN.md) | parent | Composition | Entry point | stdout is protocol-only |
| [SDK Server](https://github.com/1amageek/swift-sdk/blob/main/Sources/MCP/Server/DESIGN.md) | depends on | Server, ListTools, CallTool | Protocol owner | Use public API |
| [SDK Transport](https://github.com/1amageek/swift-sdk/blob/main/Sources/MCP/Base/Transports/DESIGN.md) | depends on | StdioTransport with explicit Limits | Bounded lifecycle | No framing copies |
| [VerificationClient](../../VerificationClient/DESIGN.md) | depends on | Core client ports and common view | Shared execution authority | Closing MCP only detaches |

## Architecture
```text
SDK stdio -> SDK Server -> Invar tool handler -> VerificationClient -> daemon
                       -> SDK SkillCatalog -> bundled skill files
```

## Contracts and Invariants
CLI and MCP submit the same typed workspace requests. Tools provide change tracking, plan, run, replay, status, cancellation, formal evidence queries and workspace watch control. Closing stdio detaches MCP observation. Durable operations and watches keep their daemon owner.

Execution uses a sealed plan and the canonical workspace. Tool arguments follow their declared schemas and cannot select an alternate workspace or direct command. Reports preserve the evidence status axes. Plan returns a bounded summary.

The CLI packages the InvarSkills target’s skill directory. The SDK builds an immutable catalog from that bundle and owns extension discovery, manifests, directory listing, and file reads. Invar advertises the manifests through standard resource discovery as well. Refer to a linked sibling skill via its own catalog entry. The catalog is independent of workspace files and requires no workspace-supplied input. Resource size is bounded under the stdio frame limit. Server instructions point agents to use-invar for preparation and missing project inputs. The Invar distribution owns skill content and versioning.

## State, Ownership, and Lifecycle
An actor owns bounded active tool calls and subscriptions under fixed limits. SDK stop/disconnect drains protocol I/O. Application shutdown detaches owned observations and closes its client session, without cancelling other observers' work.

## Failure, Concurrency, and Constraints
The SDK bounds framing and queues. Invar bounds tool concurrency and result size. Unknown or malformed arguments fail explicitly. Tools use the workspace daemon and configured runtimes.

## Verification and Change Impact
The real stdio integration exercises negotiation, tool discovery, submission, report reads, reconnect and EOF. Changes recheck the CLI, shared coordinator and SDK boundary.

[SDK transition](../../../Documentation/SDK-TRANSITION.md) owns current implementation facts, exact removal order and acceptance gates.

### Local relay
InvarMCP owns a LocalVerificationClient for its lifetime. Mutations use a stable key and return the original durable receipt. Reads include the acknowledged published view and separate source observation. Shutdown closes tracked formal leases and detaches the local client.

The local Swift MCP SDK retains framing/negotiation/dispatch ownership with1 MiB messages,16 buffered frames and5-second writes. Invar bounds concurrent tools to16. Error output is typed tool content; stdout is only MCP. Workspace and launch budget remain fixed for the process.

Successful results wrap the unchanged SDK value in a protocol-2 object (`schemaVersion`, `value`) and return matching text/structured content. The original encoded envelope is capped at300000 bytes so duplicated JSON/text framing remains within the1 MiB SDK frame bound; larger results fail explicitly and require a smaller query scope/page. No result is silently truncated or assigned an original identity after alteration.

FormalQuerySchema describes original open/catalog/graph/trace/origins/document/close discriminators and fields. Relay limits may narrow request size/count within the daemon read budget, and host validation remains authoritative. Query round-trip comparison refuses unknown fields before conversion into a typed SDK request.
