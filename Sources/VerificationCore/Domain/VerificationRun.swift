import Foundation

public struct VerificationRun: Codable, Sendable, Equatable {
    public let id: String
    public let planID: String
    public let attempts: [VerificationEvidence]
    public let associations: [EvidenceAssociation]
    public let accepted: Bool
    public let diagnostics: [String]
    public init(id: String, planID: String, attempts: [VerificationEvidence], associations: [EvidenceAssociation] = [], accepted: Bool, diagnostics: [String] = []) {
        self.id = id
        self.planID = planID
        self.associations = associations
        self.attempts = attempts
        self.accepted = accepted
        self.diagnostics = diagnostics
    }
}
