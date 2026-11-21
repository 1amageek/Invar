public protocol FormalEvidenceQuerying: Sendable {
    func formalQuery(_ query: FormalReadQuery) async throws -> FormalReadResult
}
