# Verification evidence delivery to Explorer

Invar publishes through the authorized extension protocol. Its [publication adapter](../Sources/VerificationExplorer/Publication/DESIGN.md) owns reservation, delivery and reconciliation. The [evidence contract](../Sources/VerificationCore/Evidence/DESIGN.md) owns immutable input, plan, descriptor, run, evidence and applicability references. An authorized reader can follow original evidence to Formal claims and traces at their recorded correspondence precision.

Publish against the original reserved generation and bound input. Report partial, failed, unavailable and superseded results explicitly. Reuse across inputs requires an applicability association with the exact target. Keep execution, outcome and source correspondence independent. Provide only links supported by retained records. Explorer owns subject selection, grouping and presentation.
