import Foundation

public struct SubjectReference: Codable, Sendable, Equatable {
    public let workspaceID: String
    public let snapshotID: String
    public let entityID: String?
    public let factID: String?
    public let path: String?
    public let digest: String?
    public let range: ByteRegion?
    public init(workspaceID: String, snapshotID: String, entityID: String?, factID: String?, path: String?, digest: String?, range: ByteRegion?) {
        self.workspaceID = workspaceID
        self.snapshotID = snapshotID
        self.entityID = entityID
        self.factID = factID
        self.path = path
        self.digest = digest
        self.range = range
    }
}
