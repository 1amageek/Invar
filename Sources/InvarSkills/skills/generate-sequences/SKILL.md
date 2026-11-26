---
name: generate-sequences
description: Author or review snapshot-linked interaction scenarios in the repository's SEQUENCES.dsl. Use when users want to inspect the order of calls, responses, failures, or retries between architecture elements in Explorer.
---

# Generate sequences

Work from the requested scope. Read the governing SPEC.md and any applicable design, then read the root ARCHITECTURE.dsl. If the base architecture, a participant, or a connection is missing, report the exact missing declaration and stop the affected scenario until its owner supplies it. Preserve reviewed declarations and stable IDs across edits.

Select user-visible or operationally significant scenarios from the requirements. Trace the actual production entry points, request or event path, dependency calls, owner of state changes, replies, and error handling. Read relevant tests and configuration. Keep distinct outcomes in distinct views and split them where their preconditions or results differ. Record unimplemented flows as planned in the view title and cite their specification. Keep observations and formal results with their original evidence.

## Write SEQUENCES.dsl

- Save the root file as a Structurizr workspace extending the sibling ARCHITECTURE.dsl. Define only a views block and named dynamic views. Reuse the base model's participant identifiers and static relationships. Use the software system or container that owns the use case as the dynamic scope. Use the unscoped form for people and software systems.
- Give each view a stable key and a readable title. Record requirement IDs as a space-separated invar.requirements property. List messages in execution order using the Structurizr source-to-target form, an operation label, and technology where needed to distinguish a static relationship. A response points in the reverse direction of its earlier request.
- Cite the material supporting each message immediately above it using a `// Source: path:line sha256=<digest>` comment. Use the full file's SHA-256 and a workspace-relative path. Cite the governing requirement, production statement, or test assertion as applicable. Confirm every cited line against the exact bytes and keep stale or unavailable citations visible.
- Use separate named views for alternative outcomes. The Explorer profile supports sequential messages and consecutive explicit integer order. Treat unsupported branching or ordering as a modeling gap and preserve the actual execution semantics in the review.

Validate the file with an available Structurizr parser. Open **Sequences** in Explorer and inspect the expected scenario, its Map participant, and at least one message's declaration and supporting source. Confirm the view and evidence resolve on the selected snapshot. Report the file, scenario scope, validation results and evidence gaps.
