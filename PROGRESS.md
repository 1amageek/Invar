# Invar implementation status

| Area | Implemented scope |
|---|---|
| Daemon and clients | Authenticated CLI, MCP and Swift SDK clients share one daemon per workspace. Accepted operations and watches retain their scope independently of client lifetime. |
| Input and evidence | Exact snapshot inputs, immutable run records and publication bound to the original Explorer subject. Changes to relevant inputs affect evidence applicability. |
| Project verification | Complete requirements inventory, stage reviews, evidence checks and explicit return stages for incomplete results. |
| Formal checks | Supported source profiles produce TLA+ and Lean models. Generated-model evidence records source correspondence as unvalidated. |
| Other checks | Structural policies, native oracles and bounded fuzz runs expose their own assessed scope. |

The supported host profile is macOS 27 on Apple Silicon. General Swift semantics and source-to-model correspondence remain open. See [supported profiles](Documentation/SUPPORT.md), [verification ownership](Documentation/VERIFICATION-PLAN.md) and [project workflow evidence](Verification/ProjectWorkflow-RESULT.md).

Run `python3 Tools/project-report.test.py` to exercise the report builder's evidence and review rules. The Swift package tests cover daemon, publication and assessment paths. The [system design](DESIGN.md) links to runnable integration tooling for the underlying components.
