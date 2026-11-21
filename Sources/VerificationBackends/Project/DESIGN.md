# Project verification execution

## Purpose and Scope

Execute a reviewed whole-project workflow over sealed repository inputs and retain its independently rebuilt acceptance report. Parent: [VerificationBackends](../DESIGN.md).

## Responsibilities and Boundaries

The Project component owns the approved-project-command/1 profile. It copies every declared captured input into an attempt-local workspace, preserves exact digests, invokes the approved argv with a bounded isolated process-session owner and records its logs. No shell command string is inferred. The reviewed executable and external tool/report-builder identities are checked before and after execution. Project code is host-trusted under separate native and user-Lean grants; this profile does not claim the native harness sandbox.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [VerificationBackends](../DESIGN.md) | parent | BackendContext and evidence | Composition and execution owner | No independent daemon |
| [Provider actions](../../VerificationDaemon/ProviderActions/DESIGN.md) | caller | Original action binding | Admission and confirmation | Confirmation does not grant host authority |
| [Connection](../../VerificationExplorer/Connection/DESIGN.md) | input | ProjectArchitectureReading | Complete leased files and one subject | Structural graph remains partial |

## Architecture

```text
Sealed files + approved argv -> attempt workspace -> workflow receipts
    -> pinned report builder -> validated report + retained evidence archive
    -> publisher -> original Map subject / report Canvas
```

## Contracts and Invariants

The [workflow contract](../../../plugins/invar/SPEC.md#project-workflow-gates) adds schema-2 requirement/production inventories, typed checker activities, named obligations, exact source/model bindings and five reviewed gates. The report builder derives gate status and earliest return stage; it cannot promote generation to checking. Native ProjectReportAssessment independently rejects missing claim references, workflow/review records or a verdict inconsistent with evidence. Reviews are hash-bound Agent attestations, not formal proof or execution authority. The report builder and checker producers remain host-trusted.

```text
requirements -> specification -> implementation -> correspondence -> integration
    evidence + bound review at each gate -> pass
    missing evidence/review -> incomplete -> dependent gates blocked
    review finding -> owning gate invalidated -> affected review/check repeated
```

A workflow emits one JSON summary naming a repository-relative receipt manifest and the configured report. The pinned Invar report builder independently rebuilds the report from the manifest and validates the complete acceptance inventory and receipt hashes. Input mutation, absent/empty evidence, exit/verdict disagreement and output escape fail explicitly. Only exact complete coverage across specification, implementation and validated correspondence can be passed. Incomplete and failed reports remain displayable results.

Architecture declarations are accepted as exact references from the captured workspace, including before production code exists. The requirements and integration reviews bind those declarations. ProjectBackend rejects references to documents created or changed by the workflow in its private attempt. The archive retains the declarations. The integration review owns the comparison with actual implementation and configuration.

## State, Ownership, and Lifecycle

The attempt owns its writable workspace, process journal and report artifact. Scheduler timeout/cancellation kills its owned process session. Recovery uses the existing native-processes journal. The immutable input root and live repository are not modified. A separate project-evidence/1 artifact retains the validated receipt closure, specifications, source inputs and checker logs beyond attempt cleanup. The publisher consumes a project-report/1 JSON artifact and preserves all verdict fields; it does not reinterpret incomplete as success.

The archive also owns all schema-2 review files and their input closures, declared production sources and named-obligation/model references already retained through checker receipts. Old private artifacts are preserved; no legacy successful-report reader is retained in the new assessment contract.

There is no shared mutable stored state or platform conditional in this component. Mutable buffers and CPU accounting belong to one execute invocation. WorkspaceOperations owns lifecycle and applicability in its actor; the existing process-session journal owns child cleanup. The supported execution profile remains macOS 27 arm64; WASM and Embedded execution are not advertised.

## Verification and Change Impact

Tests exercise real subprocess execution with nontrivial specification/code/correspondence outcomes, failure/timeout, changed inputs, receipt tampering, tool identity, subject binding and publication. UI checks exercise immediate destination, exact report, Back and absence of constant Map controls.
