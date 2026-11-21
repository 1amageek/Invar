# Invar Map generator

## Purpose and Scope
Offline generation of a Structurizr workspace from explicitly scoped Swift implementation and configuration. Parent: [Invar](../../DESIGN.md). No child components.

## Responsibilities and Boundaries
The caller names the system and supplies its package roots. The generator reads conventional SwiftPM executable targets and local SwiftWeb app configurations. It writes ARCHITECTURE.dsl last, after its package-owned containers.dsl and relationships.dsl fragments. Each file has a generator signature. All destinations are checked before replacement, and the next run can repair interrupted writes. Explorer owns display and verification remains with the daemon.

## Related Designs
| Design | Relationship | Contract used | Summary | Cautions |
|---|---|---|---|---|
| [Invar](../../DESIGN.md) | parent | Independent offline command | Package entry point | No daemon or store access |
| [Explorer Map](https://github.com/1amageek/ArchitectureExplorer/blob/main/Documentation/C4-CONTEXT-SPEC.md#structurizr-dsl-input) | consumer | Structurizr model and views | Snapshot-local import | Only declared facts |

## Architecture
```text
Explicit system + package roots -> parsed manifest, configuration and Swift syntax -> workspace DSL
```

## Contracts and Invariants
The named boundary covers the selected application code. A database host supplied to that code is a logical external endpoint scoped to its consumer. It makes no assertion about physical deployment or shared database identity. Library-only targets and undeclared business actors are excluded. Every emitted system is in an explicit Structurizr domain group. The selected local scope owns its runtimes. Unidentified callers and unresolved database endpoints carry explicitly scoped logical areas. A remote HTTPS authority identifies an endpoint boundary. The generator emits no placement or routing preferences. A local container carries a typed source link to the parsed entry declaration, including its UTF-8 range and input digest. The source index owns all deeper graph membership. Each inference identifies relative source locations and input digests. Repository code is never executed. A configured SwiftWeb local HTTP host or an executable entry that runs a directly
imported app through SwiftWebHTTPServerHost establishes an inbound HTTP interface.
The model represents possible inbound requests with an unspecified HTTP client
role. This denotes a capability shared by clients of those interfaces; it
does not identify a deployed caller, record traffic, or establish connections
among the hosted applications. Mere imports do not establish hosting.
Unsupported or absent evidence cannot create a dependency.

## Verification and Change Impact
Generate a multi-file model from a synthetic SwiftPM workspace, validate with the Structurizr parser, index the artifact, and inspect both Map levels. Exercise missing declarations and evidence changes independently of UI rendering.
