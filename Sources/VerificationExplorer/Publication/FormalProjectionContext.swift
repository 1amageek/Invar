import ArchitectureExtensions
import FormalEvidence
import VerificationCore

public struct FormalProjectionContext: Sendable {
    public let providerID: String
    public let view: ViewReference
    public let input: VerificationInput
    public let evidence: EvidenceSummary
    public let bundle: EvidenceArtifactReference
    public let binding: ExtensionBinding
    public init(providerID: String = "invar",view: ChangeVerificationView,evidence: VerificationEvidence,bundle: EvidenceArtifactReference,binding: ExtensionBinding) throws {
        guard ExtensionRules.validID(providerID), view.evidenceIDs.contains(evidence.id),
            let association = view.associations.first(where: { $0.evidenceID == evidence.id }), association.input == view.input,
            evidence.artifacts.contains(bundle), bundle.mediaType == "application/vnd.formal.evidence.sqlite", bundle.profile == "formal-evidence/1",
            binding.workspaceID == view.workspaceID, binding.snapshotID == view.input.snapshotID, EvidenceIdentity.validID(binding.inputManifestDigest) else { throw InvarError("INPUT_MISMATCH","Formal projection differs from its committed evidence/view/source binding") }
        self.providerID = providerID; self.view = try view.reference(); input = view.input
        self.evidence = EvidenceSummary(evidence,applicability: association.applicability); self.bundle = bundle; self.binding = binding
    }
}
