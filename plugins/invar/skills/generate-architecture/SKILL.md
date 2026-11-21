---
name: generate-architecture
description: Generate or update a repository's ARCHITECTURE.dsl when asked to model its C4 system context and containers from SPEC.md, production code and configuration.
---

# Generate architecture

Write the reviewed architecture to the target repository's root `ARCHITECTURE.dsl`. Work from the requested system and environment. Read applicable `SPEC.md` files from the working directory up to the project root and any more specific specifications governing the selected packages. Read existing architecture declarations before editing. Preserve stable identities, authored facts and unrelated scopes on updates.

## Reconcile the inputs

1. From the requirements, identify the subject, its purpose, the people or systems that interact with it and the operations they need. Use the specification to establish intent and business roles. If a scope has no applicable specification, record that gap and limit its model to what the implementation and configuration establish. Identify planned requirements separately.
2. Follow the actual production paths for the selected scope. Trace launch configuration to the executable and composition root, then follow calls, routes, consumers, storage operations and endpoint bindings to their destinations. Inspect the effective environment and infrastructure configuration where ownership or routing depends on it. A library import, directory, test double or unused adapter alone establishes no runtime connection.
3. Match each proposed element and edge to its evidence. A declared actor can be supported by a requirement and its implemented interface. A reachable call supports a capability; a configured binding supports a configured destination. Claim observed traffic only with runtime evidence. Keep planned-only interactions and unresolved destinations out of the implemented topology. Identify them with their spec or source locations in the result. If a missing input prevents resolving the subject, or evidence conflicts over the same boundary or direction, report the specific gap and preserve the affected existing declarations pending resolution.

## Write and check the model

Apply the [Structurizr rules](references/structurizr.md) when authoring and reviewing the DSL. Cite each declaration and relationship at the point of use. Reuse the same logical ID across regeneration. Review removed elements and edges against changed inputs and check the complete workspace, including existing declarations outside the edited scope.

Validate the saved root with an available Structurizr parser (with the standalone CLI: `structurizr.sh validate -workspace ARCHITECTURE.dsl`). Separately review the Invar Map rules and follow citations back to the requirement, source or binding that supports each claim. Parser success verifies DSL syntax and model consistency; the evidence review verifies what the graph says. Report the output path, scope, validation performed, and any unresolved or planned facts. State explicitly when parser validation could not run.

Explorer discovers the saved root directly. The optional Swift inventory command, `invar map`, writes to the same root and marks its outputs as generator-owned. When enriching generator output with reviewed requirements, remove the generator signature from the root so a later CLI run protects the authored contract.
