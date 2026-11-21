public struct VerificationRunSummary: Codable, Sendable, Equatable {
    public let runID: String
    public let planID: String
    public let historical: Bool
    public let acceptedAtCompletion: Bool
    public let attempts: [EvidenceSummary]
    public let diagnosticCount: Int
    public init(_ run: VerificationRun) throws {
        runID = run.id; planID = run.planID; historical = true; acceptedAtCompletion = run.accepted
        var values: [EvidenceSummary] = []
        for evidence in run.attempts {
            guard let association = run.associations.first(where: { $0.evidenceID == evidence.id }) else { throw InvarError("INVALID_RESULT","Run summary lacks its committed association") }
            values.append(EvidenceSummary(evidence,applicability: association.applicability))
        }
        attempts = values; diagnosticCount = run.diagnostics.count
    }
}
