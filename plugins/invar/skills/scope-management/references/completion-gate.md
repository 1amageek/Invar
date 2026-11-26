# Completion Gate

Consume SA Verification Findings; do not independently rerun the diff analysis. Request targeted verification if findings refer to stale inputs or do not cover required checks.

1. Check latest active requirements/scope revisions and actual final state reference.
2. Require coverage of authorized outcomes and acceptance criteria, justification of substantive changes, preserved contract evidence, and no known unauthorized edits.
3. Require all mandatory checks passed or legitimately not applicable with rationale. Failed/not-run checks prevent a fully verified completion when required. Do not count a planned check as executed.
4. Route missing work to implementation control, uncertain findings to SA, and requirement conflicts to RE/change-control. Remove only agent-introduced unjustified changes when safe and reverify the resulting state.
5. Set completion status using [the shared contract](requirements-and-scope.md). Report delivered outcomes, supporting changes, actual checks and results, approved deviations, deferred findings and blockers. Distinguish technical completion from stakeholder acceptance.

A gate result is an evidence-based judgment, not a guarantee of correctness. Do not claim user approval without evidence.
