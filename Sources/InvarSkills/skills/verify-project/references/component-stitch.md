# Run a component contract check with STITCH++

Run this check when the affected component is ready for review and its operation-order contract has a reviewed STITCH++ harness. Bind the run to the requirement IDs, named Endpoint assertions, component and exact source, dependency, harness, configuration and execution inputs. Preserve matching existing evidence under the project verification contract.

## Prepare the run

- Use a disposable copy of the reviewed inputs, including any sources referenced by the harness. Keep the harness, Dockerfile and local source path inside that copy. Review their production call boundary and assertion semantics. Use test data and local fixtures.
- Use a running local Docker engine and pin STITCH++ 0.2.0 in `stitch.toml`. Prepare the `stitch` setup profile for the harness language through Invar and use the returned Python and STITCH++ executable paths. Image preparation is a tooling step outside the Invar project sandbox.
- Retrieve [the runner](../scripts/component_stitch.py) with MCP `resources/read` and verify its manifest digest. Save it outside the captured project copy. Run it in the Agent's local environment to use Docker.

## Execute and retain evidence

Use `python3 component_stitch.py --help` for the interface. Supply the disposable workspace root, directory containing `stitch.toml`, CLI path, campaign duration, wall-clock deadline and each Endpoint that exercises a required assertion. Redirect stdout to the component review's JSON evidence file. The runner uses a fresh single-worker foreground campaign and returns exit 0 for no violation observed within budget, 5 for an observed finding or 6 for incomplete evidence. Keep the campaign output with the review while it is needed to investigate a finding. Import the JSON into the project as a supporting evidence input of the implementation review and retain the source capture reference in that review.

Treat an observed finding as a review blocker until its cause is established. For a confirmed behavioral defect, record the failing contract and return it to implementation. Record an unavailable runtime, failed invocation, invalid result or unreached required assertion as incomplete. Bounded execution evidence supports the component review. Formal assessments still require their own checker receipts.
