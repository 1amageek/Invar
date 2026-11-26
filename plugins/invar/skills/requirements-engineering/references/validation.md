# Requirements Validation

## Objective

Determine whether the requirements describe the right software for the intended stakeholders, independently of whether implementation conforms to them.

## Review checklist

- Correctness: does each requirement represent an authorized need or obligation?
- Completeness: are the necessary outcomes, relevant exceptions, and constraints covered?
- Consistency: do requirements contradict one another or preserved contracts?
- Clarity: could reasonable implementers derive materially different behavior?
- Feasibility: is there sufficient evidence that the requirement can be satisfied?
- Verifiability: are acceptance conditions observable and methods appropriate?
- Traceability: can each requirement be linked back to its source?
- Necessity: is each obligation justified without adding unrelated goals?

## Methods

Use proportionate stakeholder review, scenario walkthroughs, examples and counterexamples, prototypes, feasibility experiments, consistency checks, and formal models. Choose methods based on risk and uncertainty. A prototype can expose misunderstood behavior but does not itself constitute approval.

Distinguish validation (right requirements), specification quality review (well-formed requirements), and implementation verification (conformance). Formal proof establishes properties relative to a model and assumptions; it does not validate stakeholder intent by itself.

## Decision gate

Record each material issue as resolved, accepted by an authorized decision-maker, or open. If unresolved ambiguity affects a requirement's meaning or authorization, do not implement the affected behavior on an unsupported assumption. Continue independent authorized work where safe. A direct unambiguous request may provide sufficient authorization; do not demand redundant approval.

## Output

Record reviewed requirements, review methods, evidence, findings, unresolved issues, and stakeholder approval status. Do not label a requirement as stakeholder-approved merely because an agent reviewed it.


## Handoff
Use [the shared contract](../../scope-management/references/requirements-and-scope.md). Record results in the Requirements Baseline or its proposed revision; report material unknowns without asserting authorization.
