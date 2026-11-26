---
name: generate-architecture
description: Author or review the repository's ARCHITECTURE.dsl from requirements and design, then reconcile the C4 system context and containers with production code and configuration when available.
---

# Generate architecture

Write the reviewed architecture to the target repository's root `ARCHITECTURE.dsl`. Work from the requested system and environment. Read applicable `SPEC.md` files from the working directory up to the project root and any more specific specifications governing the selected packages. Read existing architecture declarations before editing. Preserve stable identities, authored facts and unrelated scopes on updates.

## Reconcile the inputs

1. From the requirements, identify the subject, its purpose, the people or systems that interact with it and the operations they need. Use the specification to establish intent and business roles. If a scope has no applicable specification, record that gap and limit its model to what the implementation and configuration establish. Identify planned requirements separately.
2. Before implementation, author the intended boundary, runtime units, ownership and relationships as a contract. Cite the exact requirements and accepted design decisions. Identify planned elements and relationships in their descriptions. Review the contract and keep its stable identifiers through implementation. Resolve discrepancies against the original requirements; update the contract when the design decision itself changes.
3. When implementation exists, trace launch configuration to the executable and composition root, then follow calls, routes, consumers, storage operations and endpoint bindings. Cite the production paths and effective configuration that substantiate the contract. Preserve the distinction between planned, implemented and observed relationships. Report any discrepancy or unresolved input with its owning requirement, declaration or source location for review.

## Write and check the model

Apply the [Structurizr rules](references/structurizr.md) when authoring and reviewing the DSL. Cite each declaration and relationship at the point of use. For each implemented container with a source entry, bind the runtime to its indexed declaration with the typed Entry comment in the Map profile. Reuse the same logical ID across regeneration. Review removed elements and edges against changed inputs and check the complete workspace, including existing declarations outside the edited scope.

For each C2 view, identify the real execution and data ownership boundaries. Review each area name against the specification and design: a reader should be able to tell what responsibility the area serves. Confirm in the Map that each runtime appears in its declared area and that interactions cross boundaries in the declared direction.

Validate the saved root with an available Structurizr parser (with the standalone CLI: `structurizr.sh validate -workspace ARCHITECTURE.dsl`). Follow citations back to the requirement, source or binding that supports each claim.

Before marking the task complete, run `invar` in the target Git workspace to open Architecture Explorer. For a directory without Git metadata, pass its path with `invar --workspace`. Confirm the indexed snapshot contains the saved DSL revision without a Map diagnostic. Open System Context and Containers for each system in scope, including when the DSL has no `views` block, and for every additional system with an explicit view pair. Confirm the visible actors, owned containers, boundaries and directed relationships against the declarations in that same snapshot. On each implemented container in scope with a source entry, invoke **Open components**, follow a relevant C3 component or dependency to its C4 source, and confirm the cited declaration and exact source location in Inspector. A drawn C2 node with an unresolved entry keeps this check incomplete. Record a sourced reason for containers whose role has no application entry. Record the snapshot ID and the subjects and levels inspected. Resolve ingestion or rendering failures and repeat this check. Report unavailable parser or Explorer checks and keep the corresponding validation incomplete.

Explorer discovers the saved root directly. The optional Swift inventory command, `invar map`, writes to the same root and marks its outputs as generator-owned. When enriching generator output with reviewed requirements, remove the generator signature from the root so a later CLI run protects the authored contract.
