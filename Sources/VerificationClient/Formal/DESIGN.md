# VerificationClient.Formal

## Purpose and Scope
Own remote FormalEvidenceOpening/Reading implementations over the existing authenticated daemon session. Parent: [Client](../DESIGN.md). No children.

## Responsibilities and Boundaries
Send typed query requests and preserve original FormalEvidence results. No local bundle files, SQLite, parsing, extraction or proof computation.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Client](../DESIGN.md) | parent | Authenticated session | Shared transport owner | Connection close does not stop verification |
| [Formal queries](../../VerificationFormal/Queries/DESIGN.md) | depends on | Typed requests/leases | Data-only SDK bridge | No copied formal models |

## Architecture
```text
RemoteFormalEvidenceStore -> FormalEvidenceQuerying session -> daemon
RemoteFormalEvidenceReader -> original typed pages/chunks -> caller
```

## Contracts and Invariants
A reader verifies opened bundle identity and preserves exact typed data. Explicit reader shutdown awaits remote lease/pin close and reports transport failure. The reader owns its lease independently from ordinary verification work. Closing the general session makes further reader calls fail; an unclosed reader is reclaimed by the bounded server expiry owner, never by asynchronous deinit. Raw formal values/documents require sourceValues.

## Verification and Change Impact
Behavioral tests round-trip actual tool bundles and reject cross-session access, wrong result variants and altered bundle references. Reader shutdown must release retained pins before pruning can remove an otherwise unowned bundle.

If an opening response returns a lease with a different evidence/bundle binding, the adapter closes that returned lease before rejecting it. A failed close is CLEANUP_FAILED rather than a successful reader or an unreported retained handle. A lost opening response remains subject to bounded server lease expiry. RemoteFormalOpenCleanupTests covers altered binding and close failure at this protocol boundary.
