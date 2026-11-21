import Foundation

public struct EvidenceAssociation: Codable, Sendable, Equatable {
    public let id: String
    public let targetDescriptorID: String?
    public let evidenceID: String
    public let changeRevisionID: String?
    public let input: VerificationInput
    public let basis: String
    public let applicability: String
    public let unknownBoundaries: [String]
    public let reuseDecision: String
    public init(id: String, targetDescriptorID: String? = nil, evidenceID: String, changeRevisionID: String?, input: VerificationInput, basis: String, applicability: String, unknownBoundaries: [String], reuseDecision: String) {
        self.id = id
        self.targetDescriptorID = targetDescriptorID
        self.evidenceID = evidenceID
        self.changeRevisionID = changeRevisionID
        self.input = input
        self.basis = basis
        self.applicability = applicability
        self.unknownBoundaries = Array(Set(unknownBoundaries)).sorted()
        self.reuseDecision = reuseDecision
    }
    public static func make(evidence: VerificationEvidence,targetDescriptorID: String? = nil,changeRevisionID: String?,input: VerificationInput,status: String,basis: String,unknownBoundaries: [String],reuseDecision: String) -> EvidenceAssociation {
        let normalizedUnknown = Array(Set(unknownBoundaries)).sorted()
        let id = Canonical.parts("invar.association/2",[evidence.id,targetDescriptorID.map { "present:" + $0 } ?? "absent",changeRevisionID ?? "",input.id,status,basis,reuseDecision] + normalizedUnknown)
        return EvidenceAssociation(id: id,targetDescriptorID: targetDescriptorID,evidenceID: evidence.id,changeRevisionID: changeRevisionID,input: input,basis: basis,applicability: status,unknownBoundaries: normalizedUnknown,reuseDecision: reuseDecision)
    }
}
