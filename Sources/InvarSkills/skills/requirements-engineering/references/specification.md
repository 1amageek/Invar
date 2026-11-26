# Requirements Specification

## Objective

Express analyzed requirements in a precise, maintainable, verifiable form suitable for implementation and validation.

## Authoring rules

- Use stable requirement IDs when traceability warrants them. Preserve existing IDs and conventions.
- State one independently verifiable obligation per requirement where practical. Identify the actor or system, conditions, and required observable outcome.
- Use MUST for mandatory behavior, SHOULD for justified preferences, and MAY for permitted options if consistent with project conventions. Do not use these terms to manufacture authority.
- Define relevant domain terms and units. Specify quality targets together with workload, measurement conditions, and tolerance when known.
- Include applicable failure behavior, boundary conditions, and preserved contracts. Avoid exhaustive unrelated scenarios.
- Use placeholders or explicit open decisions for missing material thresholds rather than inventing values.
- Keep rationale, acceptance criteria, and verification evidence distinct. Do not equate a test plan with an executed test.

## Suggested SPEC.md structure

Adapt the existing specification; do not impose a new format unnecessarily.

```markdown
# Specification
## Problem and goals
## Context and stakeholders
## Scope and non-goals
## Requirements
### REQ-001 — Title
- Status: proposed / authorized / superseded
- Authorization reference: required if authorized
- Source: stakeholder statement or existing decision
- Requirement: observable obligation
- Rationale: why this is needed
- Acceptance criteria: stable criterion IDs and observable conditions
- Verification method: test, inspection, analysis, or formal proof
- Dependencies and constraints: applicable references
## Preserved contracts
## Assumptions and open decisions
```

## Exit criteria

Requirements are understandable, traceable, and verifiable under stated conditions. Proposed and unresolved content is distinguishable from authorized obligations. The specification does not silently expand the outcome or prescribe unjustified implementation details.


## Handoff
Use [the shared contract](../../scope-management/references/requirements-and-scope.md). Record results in the Requirements Baseline or its proposed revision; report material unknowns without asserting authorization.
