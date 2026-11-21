import Foundation

/// Identity of verification-relevant inputs, independent of an index generation.
public enum InputIdentity {
    public static func digest(_ inventory: ScopeInventory) throws -> String {
        struct Identity: Encodable {
            let workspaceID: String
            let contextDigest: String
            let metadata: [String: String]
            let inputs: [InputEntry]
            let entities: [EntityRecord]
            let facts: [FactRecord]
            let coverage: [String]
            let evidence: [String]
        }
        return try Canonical.identity(Identity(workspaceID: inventory.workspaceID, contextDigest: inventory.contextDigest,
            metadata: inventory.metadata, inputs: inventory.inputs.sorted { $0.path < $1.path }, entities: inventory.entities.sorted { $0.id < $1.id }, facts: inventory.facts.sorted { $0.id < $1.id }, coverage: try inventory.coverage.map(Canonical.identity).sorted(), evidence: inventory.originalRecords["evidence", default: []].map(Canonical.digest).sorted()))
    }
    public static func graphDigest(_ inventory: ScopeInventory) throws -> String {
        struct Graph: Encodable {
            let workspaceID: String
            let contextDigest: String
            let entities: [EntityRecord]
            let facts: [FactRecord]
            let coverage: [String]
            let evidence: [String]
        }
        let coverage = try inventory.coverage.map(Canonical.identity).sorted()
        let value = Graph(workspaceID: inventory.workspaceID,contextDigest: inventory.contextDigest,entities: inventory.entities.sorted { $0.id < $1.id },facts: inventory.facts.sorted { $0.id < $1.id },coverage: coverage,evidence: inventory.originalRecords["evidence",default: []].map(Canonical.digest).sorted())
        return try Canonical.identity(value)
    }
}
