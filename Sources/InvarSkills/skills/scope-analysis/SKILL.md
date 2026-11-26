---
name: scope-analysis
description: Analyze task intent, justified boundaries, technical impact, and actual change evidence. Use before software changes, for read-only investigations, or when checking whether a diff is necessary and sufficient.
---

# Scope Analysis

Provide evidence-backed findings. Do not authorize, implement, revise requirements, or decide task completion.

## Workflow
Select only the phases needed. Reuse valid evidence supplied by the caller; reassess only when inputs or relevant code change.
1. [Intent analysis](references/intent-analysis.md): interpret the task mode, authorized outcome and constraints. Return material requirement ambiguities to the caller for requirements-engineering or stakeholder resolution.
2. [Boundary analysis](references/boundary-analysis.md): identify necessary and sufficient candidate changes, exclusions and preserved contracts.
3. [Impact analysis](references/impact-analysis.md): inspect dependencies and affected behavior; refine the candidate boundary.
4. [Change verification](references/change-verification.md): compare actual changes and evidence with the current baseline; check forward and reverse traceability.

## Integration
Use the [shared contract](../scope-management/references/requirements-and-scope.md). Accept a Requirements Baseline or clearly authorized direct request, and a Scope Baseline for actual verification. Return Analysis Findings or Verification Findings. Do not call requirements-engineering or scope-management: return unresolved decisions to the caller.

When used independently, report findings without granting permission to edit. If evidence is incomplete, mark unknowns; no invented thresholds, requirements, test results or approvals. Investigation scope is not modification authority. Optimize for necessary and sufficient behavior, not minimum file count.

## Result
Report findings with baseline references, evidence, classification, relevant unknowns and affected contracts. Distinguish proposed checks from checks actually executed.
