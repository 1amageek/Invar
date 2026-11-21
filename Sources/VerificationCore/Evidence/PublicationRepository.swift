public protocol PublicationRepository: Sendable {
    func loadPublication(_ id: String) async throws -> PublicationRecord?
    func savePublication(_ value: PublicationRecord,expectedRevision: Int) async throws
    func pendingPublicationIDs() async throws -> [String]
}
