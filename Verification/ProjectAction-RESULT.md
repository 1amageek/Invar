# Verified project action behavior

The [project action contract](../plugins/invar/SPEC.md#project-verification-action) identifies the admission, execution and publication requirements. Explorer owns menu navigation and rendering. Invar retains the original request, binds the captured inputs, runs the approved project command, and publishes against the original subject.

| Check | Observed behavior |
|---|---|
| [ProjectAction model](Specifications/ProjectAction/ProjectAction.tla) | TLC checked AtMostOnce, OriginalBinding, and HonestPass over nine distinct states. A mutation that made the finish verdict always pass violated HonestPass. |
| Swift backend and Python report tests | Missing evidence, changed inputs and inconsistent verdicts are rejected. A valid incomplete report is retained. |
| Explorer and MCP integration | A project report opened from the original Map subject. The completed request retained an incomplete verdict and its recorded scope. |

The TLC result concerns the bounded protocol model. Native and browser tests exercise the actual host and publication paths. The [reviewed workflow evidence](ProjectWorkflow-RESULT.md) describes the separate assessment and stage review checks.
