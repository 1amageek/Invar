public protocol EvidenceQuerying: Sendable {
    func publication(_ demandID: String) async throws -> PublicationSummary?
    func sourceHead() async throws -> SourceHead?
    func currentView() async throws -> ViewReference?
    func view(_ id: String) async throws -> ChangeVerificationView
    func runRecord(_ id: String) async throws -> VerificationRun
    func evidenceSummary(_ id: String) async throws -> EvidenceSummary
    func evidence(_ id: String) async throws -> VerificationEvidence
    func association(_ id: String) async throws -> EvidenceAssociation
}
