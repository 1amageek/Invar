public struct EvidenceSummary: Codable, Sendable, Equatable {
    public let evidenceID: String
    public let executionID: String?
    public let inputID: String
    public let jobID: String
    public let execution: String
    public let outcome: String
    public let domain: String
    public let translation: String
    public let adequacy: String
    public let applicability: String?
    public let scopeDigest: String
    public let artifactIDs: [String]
    public let diagnosticCode: String?
    public let resources: [String:Double]
    public let startedAt: String
    public let finishedAt: String
    public init(_ evidence: VerificationEvidence,applicability: String?) {
        evidenceID = evidence.id; executionID = evidence.executionID; inputID = evidence.inputID; jobID = evidence.jobID
        execution = evidence.execution; outcome = evidence.outcome; domain = evidence.domain; translation = evidence.translation
        adequacy = evidence.adequacy; self.applicability = applicability
        scopeDigest = Canonical.parts("invar.scope/2",[evidence.inputID,evidence.jobID,evidence.scope])
        artifactIDs = evidence.artifacts.map(\.id); diagnosticCode = evidence.diagnosticCode
        var measured: [String:Double] = [:]
        for name in ["wallSeconds","cpuSeconds","sampledPeakResidentBytes","sampledPeakProcesses"] {
            if let value = evidence.resources[name] { measured[name] = value }
        }
        resources = measured; startedAt = evidence.startedAt; finishedAt = evidence.finishedAt
    }
}
