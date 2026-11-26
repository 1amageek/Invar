---
name: scope-management
description: Establish and control the authorized boundary of software work, manage changes, and decide completion from scope-analysis evidence. Use for implementation, refactoring, migrations, and other software modifications.
---

# Scope Management

Own the Scope Baseline and execution control. Deliver authorized outcomes completely without unrelated changes. Only the user or a documented authorized stakeholder can approve expansion.

## Workflow
1. [Baseline](references/scope-baseline.md): obtain requirements or direct request, request scope-analysis, and establish the authorized work boundary.
2. [Control](references/scope-control.md): compare proposed and actual work with that boundary; request targeted analysis only when necessary.
3. [Change control](references/change-control.md): route material changes to requirements-engineering and the authority holder; resume only affected work after authorization and rebaselining.
4. [Completion gate](references/completion-gate.md): consume scope-analysis verification findings, enforce required checks and report status.

## Integration
Use the [shared contract](references/requirements-and-scope.md). Coordinate scope-analysis as the sole owner of technical boundary/impact/diff analysis. Obtain requirements-engineering results when requirements are ambiguous, new, or changed. Do not duplicate their procedures. A caller may dispatch skills directly or load their instructions in the same agent; no special runtime is assumed.

If a required skill is unavailable, report the gap and perform only independently authorized work that can be justified; do not claim a completed analysis or gate without evidence. For read-only requests, do not modify software. Preserve existing user changes and unrelated contracts.

For clear small changes, use compact records; no mandatory SCOPE.md or additional tracking files.

## Result
Return baseline reference, delivered outcomes, approved deviations, actual checks, unresolved blockers, deferred findings and completion status.
