# Invar repository instructions

Apply the global development rules to changes in this repository. Read [PHILOSOPHY.md](PHILOSOPHY.md) for the product responsibilities and the [implementation design](DESIGN.md) for their technical owners.

## Workflow authority

- Define the executable Agent workflow in the MCP-distributed [verify-project skill](Sources/InvarSkills/skills/verify-project/SKILL.md). It owns stage order, pass conditions, reviews and return behavior. Delegate scoped work to [verify-spec](Sources/InvarSkills/skills/verify-spec/SKILL.md) and [formal-verification](Sources/InvarSkills/skills/formal-verification/SKILL.md). Keep this file a repository guide.
- Begin at the selected project directory and read applicable requirements upward through the project root. Where requirements are missing, use the user's request to author `SPEC.md` in the owning scope and review it before advancing. Resolve gaps that would change the expected behavior with the user. Support this entry point even when a project has zero source files and no architecture model.
- For new or changed implementation, identify the necessary contracts in `SPEC.md`, then complete **Specification Verification** and its review before writing the affected production code. After implementation and tests, complete **Implementation Model Verification**, **Source-to-Model Validation**, and integration review. Return findings to their owning stage and rerun affected checks and reviews. See the [evidence contract](Sources/InvarSkills/skills/verify-project/references/project-verification.md).

## Execution and evidence

- Use Invar's CLI or MCP path for workflow verification. Invar owns admission, the captured inputs, checker execution, receipts, verdict derivation and publication. Direct tool runs may inform debugging. A workflow gate requires the actual Invar execution record and a review bound to its inputs.
- Keep requirements-derived models separate from implementation-generated models. Record test evidence, formal claims, source correspondence and publication status at their actual scope. Keep missing evidence, unsupported inputs and undecided correspondence explicit. Use a passed project verdict only when all required checks and reviews pass.
- Preserve the same workspace, subject and exact input binding across Explorer and Agent interactions. Expose specification and project verification from the Workspace, including before source code or a C4 Map exists. Treat reopening evidence as a read operation and show the verification destination before waiting for its data.

## Review behavioral changes

- For changes to workflow entry, execution, publication or evidence navigation, verify the affected behavior in the actual CLI/MCP and Explorer paths using the same workspace and snapshot. For changes across the whole workflow, reproduce a project with no `SPEC.md` or production source, review and verify the written specification before adding code, then exercise the post-implementation gates and confirm that Explorer shows the outcome. Include an incomplete or failed path with the correct return stage.
- When validating skill delivery, connect an agent to Invar MCP and observe skill lookup, reference reads and verification execution in the intended workspace.
- Report missing behavior explicitly during review. Documentation and skill text define the required behavior. CLI runs, MCP receipts and the Explorer view establish what works in the current build.
