# Requirements Analysis

## Objective

Transform elicited needs into a coherent set of candidate requirements while identifying conflicts, dependencies, feasibility risks, and missing behavior.

## Procedure

1. Classify candidate requirements: functional behavior, quality attributes, interfaces and data contracts, and mandated constraints. Include security, privacy, accessibility, reliability, or legal obligations only where applicable; establish their source.
2. Identify actors, system boundaries, preconditions, inputs, state transitions, outputs, and error conditions relevant to the requested outcome.
3. Examine dependencies and existing contracts. Distinguish behavior that must change from behavior that must be preserved. Request technical boundary and dependency findings from `scope-analysis` through the caller; reuse existing evidence.
4. Find ambiguity, duplication, contradictions, missing cases, circular dependencies, and unsupported assumptions. Resolve using authorized evidence; escalate material conflicts rather than choosing silently.
5. Assess technical and operational feasibility using available evidence. Separate feasibility from desirability. Record unknowns and proposed experiments; do not silently reduce a requirement to fit current implementation.
6. Prioritize requirements only using stakeholder decisions or established project criteria. Mark proposed priorities as such. Do not treat an inferred preference as mandatory.
7. Determine observable acceptance conditions and candidate verification methods. Flag requirements that cannot yet be verified.

## Decision rules

- Prefer requirements that express outcomes rather than mechanisms unless a mechanism is explicitly mandated.
- Distinguish necessary supporting behavior from speculative future needs.
- Existing bugs are not automatically intended behavior; existing contracts are not automatically authorized to change.
- A newly discovered requirement remains a candidate until its authority is established.

## Output

A coherent candidate requirement set, source links, dependencies, preserved contracts, relevant scenarios, feasibility findings, conflicts, and open decisions. Material unresolved requirements must be marked as such and must not be presented as ready for unconditional implementation.


## Handoff
Use [the shared contract](../../scope-management/references/requirements-and-scope.md). Record results in the Requirements Baseline or its proposed revision; report material unknowns without asserting authorization.
