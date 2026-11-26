---
name: verify-spec
description: Run Specification Verification on scoped contracts from SPEC.md using TLA+ and Lean. Use before implementation or for the specification stage of verify-project, including projects without source code or an Explorer snapshot.
---

# Specification Verification

Derive obligations from the applicable `SPEC.md` and execute the relevant checkers. Work in the target repository. Keep the requirements-derived models separate from artifacts translated from implementation.

Whole-project orchestration belongs to [verify-project](../verify-project/SKILL.md). When assigned its specification stage, execute only that stage and return scoped receipts, review findings and uncovered conditions to the orchestrator. A directly requested design check does not require implementation or publication. User-requested condition definition remains a definition-only operation.

## Establish the contract

Read the specifications from the working directory up to the project root and the more specific requirements for the selected scope. Record the owning path, heading or requirement ID for each obligation. Identify inputs, allowed states and operations, required outcomes, failure cases and environmental assumptions. Resolve conflicting requirements before checking the affected obligation; report ambiguous or missing requirements explicitly. Use the specification as the oracle throughout.

Choose TLA+ for interacting operations, schedules, safety and liveness; choose Lean for quantified invariants, pre/postconditions and mathematical contracts. Use both when a requirement has both aspects and explain the correspondence between their states, operations and assumptions. Each result applies to the obligation it actually checks.

## Author and run

For a project gate, configure the actual checker commands, expected named obligations, exact model inputs and bounded outputs in the host-reviewed Invar project workflow. Submit the check through the daemon and inspect the retained receipts before reviewing the gate. The direct checker commands below describe the processes that the workflow invokes and can also be used for scoped standalone diagnostics.

Reuse the repository's location for design verification. Otherwise keep the reviewed `.tla`, `.cfg` and `.lean` inputs in `Verification/Specifications/<subject>/`. Cite the requirement in the model next to its named property or theorem. Keep checker scratch files in a fresh temporary directory for each run. Use the repository's pinned toolchain or the corresponding binaries from a locally verified swift-formal distribution. Record tool identities, exact commands, input revisions or digests, and an explicit time budget. If a required tool or input is unavailable, mark its obligation unexecuted.

**TLA+.** Define the initial states and allowed transitions independently of the property being tested. Configure TLC with the intended specification, finite constants, and each named `INVARIANT` or temporal `PROPERTY`. Justify model bounds, termination, deadlock policy and any fairness or pruning assumptions. Run the actual checker with a deadline:

```sh
timeout "$seconds" "$java" -Djava.io.tmpdir="$scratch" -cp "$tla_jar" tlc2.TLC -workers 1 -metadir "$scratch/states" -config "$config" "$module"
```

Check that TLC loaded the intended configuration, explored reachable states, and completed the requested exhaustive run. Report distinct states, bounds and the checked properties. For a violation, retain the initial state and the actions and states of the counterexample, including any liveness loop. A parser run, simulation, timeout or truncated search cannot establish an exhaustive result.

**Lean.** Express the required guarantee as a named theorem over the specified domain. Formalize the operation and preconditions independently of its conclusion. Check that the premises are satisfiable and that named boundary cases have their intended meaning. Include `#print axioms` for each reported theorem. Run Lean on the exact module under the project's pinned dependencies:

```sh
timeout "$seconds" "$lean" -DwarningAsError=true "$proof_file"
```

For a Lake project use its existing `lake env lean` invocation. Inspect the checked theorem statement and its axiom output. Accept a proof only on successful elaboration with no admissions and an audit containing only the allowed foundations (the swift-formal policy permits `propext`, `Classical.choice` and `Quot.sound`). A failed proof is an open obligation; a counterexample requires an actual witness.

## Review the result

For each requirement, give the formal statement, its correspondence to the original wording, assumptions, input paths, checker evidence, and uncovered cases. Keep a concise reproducible result alongside the specifications or in the repository's existing verification record. When an input changes, rerun the affected obligations. Review a nontrivial model for vacuity: confirm a meaningful operation is reachable or a relevant premise can hold, and exercise a violating case when it distinguishes a real guarantee from a tautology.

Report bounded TLC success, Lean proof, counterexample, and incomplete execution separately. Return a wrong requirement to requirements and an incorrect or incomplete formalization to specification. Preserve the original requirement when diagnosing implementation failures. In a project workflow, record the bound stage review using the [evidence contract](../verify-project/references/project-verification.md). Source-to-Model Validation and project completion remain the orchestrator's responsibility.
