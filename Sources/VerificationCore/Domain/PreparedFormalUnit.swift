import Foundation

public struct PreparedFormalUnit: Codable, Sendable, Equatable {
    public let id: String
    public let sourceDigest: String
    public let language: String
    public let executorIdentity: String
    public let manifest: EvidenceArtifactReference
    public let evidence: EvidenceArtifactReference
    public init(id: String,sourceDigest: String,language: String,executorIdentity: String,manifest: EvidenceArtifactReference,evidence: EvidenceArtifactReference) {
        self.id = id; self.sourceDigest = sourceDigest; self.language = language; self.executorIdentity = executorIdentity; self.manifest = manifest; self.evidence = evidence
    }
    public static func key(sourceDigest: String,language: String,executorIdentity: String) throws -> String {
        try Canonical.identity(["profile":"formal-preparation/2","source":sourceDigest,"language":language,"executor":executorIdentity])
    }
}
