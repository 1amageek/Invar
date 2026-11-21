import Foundation

public struct ScopeInventory: Codable, Sendable, Equatable {
    public let workspaceID: String
    public let snapshotID: String
    public let contextDigest: String
    public let metadata: [String: String]
    public let entities: [EntityRecord]
    public let facts: [FactRecord]
    public let coverage: [CoverageRecord]
    public let inputs: [InputEntry]
    public let originalRecords: [String: [Data]]
    public let diagnostics: [String]
    public init(workspaceID: String, snapshotID: String, contextDigest: String, metadata: [String: String], entities: [EntityRecord], facts: [FactRecord], coverage: [CoverageRecord], inputs: [InputEntry], originalRecords: [String: [Data]] = [:], diagnostics: [String] = []) {
        self.workspaceID = workspaceID
        self.snapshotID = snapshotID
        self.contextDigest = contextDigest
        self.metadata = metadata
        self.entities = entities
        self.facts = facts
        self.coverage = coverage
        self.inputs = inputs
        self.originalRecords = originalRecords
        self.diagnostics = diagnostics
    }
}
