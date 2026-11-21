# VerificationBackends.Native

## Purpose and Scope
Build exact captured standalone Swift modules and run explicit native JSON-oracle harnesses, including one bounded seeded signed-integer fuzz profile. Parent: [Backends](../DESIGN.md). No children.

## Responsibilities and Boundaries
Own the macOS sandbox/compiler adapter, native result classification and deterministic fuzz/replay/minimization. The host provides approved module sources, independent harness oracle, tool paths and budgets. No SwiftPM scripts/plugins, dependency download, inferred oracle or arbitrary shell is used.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Backends](../DESIGN.md) | parent | VerificationBackend | Method-specific execution | Native evidence is not model proof |
| [Core](../../VerificationCore/DESIGN.md) | depends on | Native/Fuzz checks and immutable context | Explicit authority | No graph-to-runtime inference |
| [Formal ToolExecution](https://github.com/1amageek/swift-formal/blob/main/Sources/FormalValidation/ToolExecution/DESIGN.md) | depends on | Owned bounded subprocesses | Generic process owner only | No formal semantics reused for native code |

## Architecture
```text
Captured module DAG + harness + pinned compiler/SDK/tools -> sandboxed swiftc
    -> binary digest -> sandboxed native JSON oracle -> scoped evidence
                   -> corpus/seeded signed64 inputs -> same oracle -> checked shrinking
```

## Contracts and Invariants
Only macOS 27 arm64 `swift-modules-json/1` is supported. Original source bytes are copied from the sealed input root, hash-checked and built without reading the live workspace. The compiler toolchain, linker toolchain and SDK receive complete bounded file/mode/symlink inventory hashes before/after use; OS build and exact flags are part of the environment identity. Host system libraries are an explicit trusted OS assumption, not captured project code.

The build sandbox reads only system libraries, declared compiler/SDK/tools and attempt files, and writes only the attempt. The execution sandbox reads system/runtime/attempt bytes, denies network/Mach lookup, cannot read the live workspace or user credentials and cannot fork/escape its owned group. Probe these actual denials before enabling the profile; unsupported enforcement is ISOLATION_UNAVAILABLE. A separate worker alone is not sandboxing.

Native success requires exact expected test count >0 and versioned JSON oracle `schemaVersion=1, testsRun, holds`; empty output, malformed reports, compilation failure and runner failure cannot pass. An explicitly expected signal is separate from unexpected native failure. A nonzero/crash or holds=false in fuzzing is retained as an original counterexample; shrinking retains only candidates reproducing the same failure classification. Corpus, seed, encoding, binary, environment, original/minimal inputs and private logs remain recorded.

A completed fuzz budget with no witness has outcome noViolationObservedWithinBudget, not a proof. CI may accept that bounded contract only through the check's explicit acceptance flag. No coverage-guided, sanitizer or arbitrary-project support is claimed.

## State, Ownership, and Lifecycle
Attempt-local tool inventories, build outputs, corpus/PRNG state and process invocations. Build/hash workers inject inherited-group runners. The coordinator directly owns native processes as isolated-session leaders under the no-fork sandbox, with durable launch intent/PID/terminal records outside the sandbox writable root. Startup recovery stops unfinished sessions before replacement admission. NativeSessionExecutor accounts build, execution and postflight CPU; all coordinator CPU during its interval is included conservatively as an upper bound, including concurrent controller work. All derived outputs are under the private attempt root.

## Failure, Concurrency, and Constraints
At most 32 modules/256 sources/1000 corpus inputs plus 1000 generated samples/32 shrink attempts; existing input and attempt budgets apply. Tool inventory bounds are 250000 entries, 16 GiB and 60 seconds. Hashing streams 1 MiB buffers. Directory traversal derives relative paths from enumerator depth rather than lexical root-prefix lengths, preserving entries when macOS presents `/var` and `/private/var` aliases differently. Enumeration and every file-read chunk check task cancellation before further work; cancellation closes the current file before returning and never produces an environment identity. Unknown external roots/symlinks, cyclic module dependencies, unsupported target and unenforceable isolation fail explicitly. Runtime never installs tools.

## Verification and Change Impact
Actual native fixtures cover two-module contracts, false oracle, empty test count, expected trap/unexpected crash, sandbox file/network/fork/group denial, original/minimal fuzz witness and replay. Mutating a module/oracle/tool identity invalidates the plan. Changes recheck Planner, Store, admission and CI domains.

Direct build services report wall time and process-wide CPU deltas (self plus reaped children), a conservative upper bound if the caller concurrently performs other work. Isolated workers replace these with externally measured group accounting. Empty resource dictionaries are rejected.

The environment identity retains both the invoked compiler path (including driver basename) and the resolved executable content. A symlinked swiftc invocation is not interchangeable with invoking swift-driver directly.

The captured input manifest, exact bytes and explicit Swift build profile authorize native compilation independently of structural parsing. An Explorer parser failure remains a diagnostic; it does not suppress an approved native check of a captured Swift file. Native execution does not require a parsed file entity.

The reproductionKey binds native failure classification and oracle count, or fuzz input encoding/original input/classification. Binary/environment identities are retained separately. A rebuilt binary is not claimed bit-identical; unchanged plans retain exact source/tool/oracle bindings.

NativeInventoryCancellationTests exercises the actual inventory on macOS temporary-directory aliases, stable identities and changed tool bytes. The opt-in sparse-file cancellation case (`INVAR_NATIVE_CANCELLATION_PROBE=1`) cancels during one large regular artifact and requires cleanup/return within one second; it does not execute a native tool or certify compiler sandboxing.
