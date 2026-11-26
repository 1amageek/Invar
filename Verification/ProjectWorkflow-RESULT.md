# Reviewed project verification evidence

[Verify Project](../Sources/InvarSkills/skills/verify-project/SKILL.md) runs the project workflow and reviews. The [verification contract](../Sources/InvarSkills/SPEC.md#project-workflow-gates) defines gate, coverage and evidence requirements.

| Evidence | Observed result |
|---|---|
| [TLA+ gate model](Specifications/ProjectWorkflow/ProjectWorkflow.tla) | TLC explored 2,388 distinct states and checked NoFalsePass, PrefixReviewed and ReturnToOwner. Removing the review guard violates PrefixReviewed. A fully reviewed pass is reachable. |
| [Lean gate model](Specifications/ProjectWorkflow/ProjectWorkflow.lean) | Four theorems check the required evidence and review decisions. The proofs use only propext. |
| Python report checks | 23 tests cover exact evidence references, wrong domains, named obligations, missing reviews, production coverage and return-stage propagation. |
| Swift package checks | 148 tests across 40 suites, including actual builder reports, rejected inconsistent verdicts, process deadlines and fixed-input checks. |
| Explorer and MCP | The real project publication path retains an incomplete report with a return stage. The Canvas preserves the whole-project verdict while filtering. |

The models establish their bounded gate properties. The behavioral tests exercise the receipt and report implementation. The project verdict requires independent Specification Verification, Implementation Model Verification, Source-to-Model Validation, and the required stage reviews.

To run the model checks, use the pinned TLC tool with [ProjectWorkflow.cfg](Specifications/ProjectWorkflow/ProjectWorkflow.cfg) and run the Lean kernel on the Lean model. For report checks, run `python3 Tools/project-report.test.py` with a timeout. See the [receipt and review contract](../Sources/InvarSkills/skills/verify-project/references/project-verification.md) for the fields required to reproduce a report.
