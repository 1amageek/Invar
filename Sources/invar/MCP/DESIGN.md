# invar.MCP

## Purpose and Scope
Compose the user-selected local [Swift SDK](https://github.com/1amageek/swift-sdk/blob/main/DESIGN.md) into the Invar CLI. Parent: [invar](../DESIGN.md). No children.

## Responsibilities and Boundaries
The SDK owns protocol versions, codec, negotiation, stdio framing and request dispatch. Invar owns tool schemas, workspace/configuration authority, bounded projections and typed client requests. No second MCP implementation is introduced.

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
```

## Contracts and Invariants
Implemented SDK revision. Use the same VerificationClient protocols/view revision as CLI and Explorer. Remove per-MCP Store ownership and local plan/discovery generation. Tools expose change begin/seal/view, plan preparation, run/replay/status/cancel, graph/trace/origin/artifact queries and authorized watch control. Read tools never trigger inspection/execution. Startup authority is pinned by daemon policy; tool arguments cannot widen it. Process/stream close detaches observation while durable changes/watches/work remain. AsyncStream owners finish/drain on shutdown.

Execution is disabled unless startup scope and current daemon policy explicitly grant it. Run/replay must match the approved normalized contract/configuration digest and canonical workspace; tool arguments cannot supply a new grant, policy, executable, shell or file root. The old Bool option is removed at the daemon cutover. Read tools are marked separately. Reports paginate immutable attempts, omit source/log/private paths and preserve all status axes. Plan returns a bounded summary rather than source-bearing inventory.

## State, Ownership, and Lifecycle
An actor owns bounded active tool calls and subscriptions under negotiated daemon policy. SDK stop/disconnect drains protocol I/O. Application shutdown detaches owned observations and closes its client session, without cancelling other observers' work.

## Failure, Concurrency, and Constraints
Frame/queue/write/result caps are bounded by the MCP transport and daemon policy; current defaults are implementation facts, not new SDK constants. Unknown/malformed arguments fail explicitly. Tools use only approved local profiles and never install runtimes. Source/log strings remain data. Unsupported Tasks/elicitation/sampling are not advertised.

## Verification and Change Impact
Actual SDK Server stdio integration covers initialize, tool discovery, read-only execution refusal, approved submission/status/report, cancellation/EOF and malformed/oversized input. Changes recheck CLI authority, shared coordinator and the SDK public boundary.

[SDK transition](../../../Documentation/SDK-TRANSITION.md) owns current implementation facts, exact removal order and acceptance gates.

### Protocol-2 relay cutover
InvarMCP owns one authenticated LocalVerificationClient/profile for its lifetime. Tool availability follows actual granted capabilities, not caller Booleans or local configuration reads. Mutations require an explicit stable key and return the original durable receipt immediately. Reads return SDK values, including the acknowledged published default and separate source observation. Private formal queries retain their server lease handles through the live MCP session; EOF/shutdown closes tracked handles before closing the client, and never cancels accepted operations/watches. Original cursors are valid only while that session/reader remains open. Unknown delivery returns the fixed PreparedOperation and cause, never a fresh submission.

The local Swift MCP SDK retains framing/negotiation/dispatch ownership with1 MiB messages,16 buffered frames and5-second writes. Invar bounds concurrent tools to16. Error output is typed tool content; stdout is only MCP. Startup capability ceiling and budgets remain fixed for the process, and no tool argument can change them.

Successful results wrap the unchanged SDK value in a protocol-2 object (`schemaVersion`, `value`) and return matching text/structured content. The original encoded envelope is capped at300000 bytes so duplicated JSON/text framing remains within the1 MiB SDK frame bound; larger results fail explicitly and require a smaller query scope/page. No result is silently truncated or assigned an original identity after alteration.

FormalQuerySchema describes original open/catalog/graph/trace/origins/document/close discriminators and fields. Relay limits may narrow request size/count within host capability, and host validation remains authoritative. Query round-trip comparison refuses unknown fields before conversion into a typed SDK request.
