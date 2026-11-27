---
name: code-review
description: Review a pull request, branch, commit, or working-tree change for actionable defects, regressions in related features, and material verification gaps. Use for code review, PR review, implementation review, コードレビュー, or 差分レビュー.
---

# Code Review

Deliver a read-only review grounded in the expected behavior, the affected execution paths, and evidence. Follow the repository's review, scope, and verification instructions. Run scoped checks with timeouts, avoid external or shared-environment side effects, keep probes or generated evidence outside the reviewed source tree, and ensure the working tree stays unmodified.

## 1. Establish the target and expected behavior

- Resolve the exact comparison and included changes. Use the intended target and merge base for a branch or PR to identify the change set; when the target branch has advanced past the merge base, also inspect target-side changes touching the same contracts or dependency paths. For a working-tree review, include staged, unstaged, and relevant untracked files. Inspect the complete change, including removals and changes to tests, configuration, and packaged inputs.
- Read the applicable requirements, specifications, design decisions, and compatibility commitments. Establish the intended behavior and what existing consumers still rely on. Cite the authority for each material expectation. Label expectations inferred from callers, tests, or baseline behavior as such. Resolve conflicts by authority where possible and hold any affected judgment while a material conflict remains unresolved.
- Express each affected guarantee as a claim with conditions and a result. Identify who owns it, what callers or the environment must provide, what success and failure allow, and which properties must hold across transitions. Check whether the intended behavior serves the stated use as well as whether the implementation conforms to its specification.

## 2. Trace the impact on related features

- Trace each material change from the real entry point through dispatch, implementation, dependencies, and observable outcomes. Trace relevant guarantees back from the requirements or existing callers to their owners and execution paths. Use both directions to find omitted implementation and dependencies beyond the diff.
- Follow changed assumptions through direct and transitive consumers, including unchanged features. Trace shared state and data, events and background processing, configuration and permissions, and common resources as well as explicit calls. Follow producers when the change alters what a feature expects to receive. Check active configurations and supported versions where they affect reachability.
- For each potentially affected feature, identify the dependency and the observable behavior or guarantee at stake. Stop tracing a branch once evidence establishes that the consumer-facing guarantee and its relevant assumptions still hold. Record the feature, condition, and missing dependency or environment when a material path cannot be resolved.
- Select applicable checks from [review probes](references/review-probes.md) to challenge what the impact trace assumes. Scale depth to consequence and uncertainty: keep low-risk, narrow changes lightweight; for large changes, prioritize public boundaries, state transitions, persistence, and trust boundaries first, and record any deprioritized areas as gaps.

## 3. Test claims and look for counterexamples

- Exercise the real entry point for material behavioral claims and select the boundary, failure, or interaction that could disprove the guarantee. When the target branch has advanced and modifies the same contracts or dependency paths, exercise the affected entry points against the integrated (merged) result outside the reviewed source tree, or record those paths as unresolved gaps if an integrated result cannot be constructed. Use existing checks when their setup reaches the relevant implementation and their assertions observe the affected outcome. Use a focused probe when they miss a material condition. Compare with the baseline where it helps distinguish a regression from an existing issue.
- Choose evidence that answers the claim. Source inspection can establish an unambiguous reachable contradiction or structural fact. Build, static analysis, model checking, and runtime checks each support claims within their own scope. Record the revision, execution variant, and conditions that matter. Establish how a model corresponds to the implementation before relying on it for an implementation claim.
- Continue across the full review target after a finding. Reconcile the affected guarantees and related features with the evidence. For each material path, identify the result, demonstrated violation, or unresolved gap. Distinguish gaps in the review from deficiencies in the change's verification.

## 4. Return the review

- Structure the response as: **Verdict**, **Findings**, **Coverage & Gaps**, and **Checks Run**.
- Lead **Findings** with actionable items ordered by severity (`Blocker`, `High`, `Medium`, `Advisory`). Include the changed location (`file:line` and symbol), triggering condition (with a minimal concrete counterexample when disproving an assumption), actual outcome, violated guarantee, and supporting evidence (command output, trace, or cited authority). Cite any unchanged downstream code needed to establish the effect. Combine symptoms with the same cause and remedy, while naming the affected features. Provide a concise concrete suggestion when the fix is small and unambiguous, and keep open clarifying questions distinct from demonstrated defects. Anchor inline comments to the smallest relevant change when supported.
- Judge severity by consequence, reach, and likelihood. Include defects introduced or made reachable by the change, and concrete violations of contracts the change owns. Keep independent existing issues outside the decision. Treat style preferences as `Advisory`.
- Apply verdict precedence strictly: **Changes requested** (any demonstrated violation that blocks the intended outcome) > **Verification incomplete** (no blocking defect found, but a material gap prevents a sound decision) > **No blocking findings** (material claims are adequately supported). State separately when there are no actionable findings.
- Summarize material coverage in **Coverage & Gaps** with a compact mapping from guarantee to affected feature, path or variant, and evidence or gap. Name the checks that ran and their results in **Checks Run**. Surface material gaps even when a confirmed defect already decides the review.
