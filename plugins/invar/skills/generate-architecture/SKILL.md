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

Apply the [Structurizr rules](references/structurizr.md) when authoring and reviewing the DSL. Cite each declaration and relationship at the point of use. Reuse the same logical ID across regeneration. Review removed elements and edges against changed inputs and check the complete workspace, including existing declarations outside the edited scope.

For each C2 view, trace where the client app executes, where the backend executes, and which side owns each data store. When a system has both a client app and a separately running backend, declare them in sibling `App` and `Backend` groups within that system. Confirm in the Map that each runtime appears in its declared area and that the client-to-backend interaction crosses the boundary in the declared direction.

Validate the saved root with an available Structurizr parser (with the standalone CLI: `structurizr.sh validate -workspace ARCHITECTURE.dsl`). Separately review the Invar Map rules and follow citations back to the requirement, source or binding that supports each claim. Parser success verifies DSL syntax and model consistency; the evidence review verifies what the graph says. Report the output path, scope, validation performed, and any unresolved or planned facts. State explicitly when parser validation could not run.

Explorer discovers the saved root directly. The optional Swift inventory command, `invar map`, writes to the same root and marks its outputs as generator-owned. When enriching generator output with reviewed requirements, remove the generator signature from the root so a later CLI run protects the authored contract.
