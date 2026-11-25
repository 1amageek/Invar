# Impact Analysis

## Trace the change

Start with the changed behavior and responsible component. Inspect architecture descriptions, source, tests, configurations, and runtime contracts as available. Trace upstream callers, downstream dependencies, shared state, and external consumers. Follow transitive paths when a plausible effect exists; stop when evidence establishes that a boundary isolates the effect. Record unknown paths rather than claiming exhaustive coverage.

Consider public APIs, data schemas and migrations, persistence, concurrency, security, privacy, performance, resource usage, deployment, compatibility, and failure behavior when relevant. Distinguish static dependency evidence from observed runtime behavior. Static analysis may miss dynamic dispatch, reflection, configuration, or external consumers.

## Classify findings

Use the six canonical classifications in [the shared contract](../../../references/requirements-and-scope.md); do not define alternative labels.

For each material impact record the affected entity, causal path, evidence, potential consequence, necessary response, and confidence. Distinguish an affected component from one that must be edited. Consider alternatives before recommending wider changes. Do not treat risk severity as automatic authorization.


## Handoff
Use [the shared contract](../../../references/requirements-and-scope.md) for identifiers, classification, check status and baseline revisions. Return findings to the caller; do not authorize or apply changes.
