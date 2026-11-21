import FormalEvidence

public struct FormalReadLease: Codable, Sendable, Equatable {
    public let id: String
    public let epoch: String
    public let evidenceID: String
    public let reference: EvidenceBundleReference
    public let expiresAt: Double
    public init(id: String,epoch: String,evidenceID: String,reference: EvidenceBundleReference,expiresAt: Double) {
        self.id = id; self.epoch = epoch; self.evidenceID = evidenceID; self.reference = reference; self.expiresAt = expiresAt
    }
}
