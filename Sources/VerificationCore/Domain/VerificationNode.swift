public struct VerificationNode: Codable, Sendable, Equatable {
    public let snapshotID: String
    public let entityID: String
    public init(snapshotID: String, entityID: String) {
        self.snapshotID = snapshotID
        self.entityID = entityID
    }
}
