import Foundation

public struct VerificationInput: Codable, Sendable, Equatable {
    public let id: String
    public let workspaceID: String
    public let snapshotID: String
    public let manifestDigest: String
    public let sourceIdentity: String
    public let semanticDigest: String
    public let graphDigest: String
    public let graphClosureComplete: Bool
    public let contextDigest: String
    public let dependencyStatus: String
    public let entityCount: Int
    public let factCount: Int
    public let fileCount: Int
    public let byteCount: Int
    public init(id: String, workspaceID: String, snapshotID: String, manifestDigest: String, sourceIdentity: String, semanticDigest: String, graphDigest: String, graphClosureComplete: Bool, contextDigest: String, dependencyStatus: String, entityCount: Int, factCount: Int, fileCount: Int, byteCount: Int) {
        self.id = id
        self.workspaceID = workspaceID
        self.snapshotID = snapshotID
        self.manifestDigest = manifestDigest
        self.sourceIdentity = sourceIdentity
        self.semanticDigest = semanticDigest
        self.graphDigest = graphDigest; self.graphClosureComplete = graphClosureComplete
        self.contextDigest = contextDigest
        self.dependencyStatus = dependencyStatus
        self.entityCount = entityCount; self.factCount = factCount
        self.fileCount = fileCount
        self.byteCount = byteCount
    }
    public static func reference(_ inventory: ScopeInventory) throws -> VerificationInput {
        var total = 0
        for file in inventory.inputs {
            guard file.byteCount >= 0, file.byteCount <= Int.max - total else { throw InvarError("INVALID_INPUT", "Invalid input byte accounting") }
            total += file.byteCount
        }
        let id = try Canonical.identity(inventory)
        let semantic = try InputIdentity.digest(inventory)
        let graph = try InputIdentity.graphDigest(inventory)
        let complete = !inventory.coverage.isEmpty && inventory.coverage.allSatisfy { $0.freshness == "current" && $0.completeness == "completeWithinScope" && $0.exclusions.isEmpty }
        let sourceIdentity: String
        if let originals = inventory.originalRecords["inputManifest"] {
            guard originals.count == 1, let manifest = originals.first, !manifest.isEmpty else { throw InvarError("INPUT_MISMATCH","Source authority needs exactly one original input manifest") }
            sourceIdentity = Canonical.parts("invar.explorer-source/2",[inventory.workspaceID,inventory.snapshotID,inventory.contextDigest,graph,Canonical.digest(manifest)])
        } else {
            sourceIdentity = Canonical.parts("invar.captured-source/2",[inventory.workspaceID,inventory.snapshotID,inventory.contextDigest,semantic])
        }
        return VerificationInput(id: id,workspaceID: inventory.workspaceID,snapshotID: inventory.snapshotID,manifestDigest: id,sourceIdentity: sourceIdentity,semanticDigest: semantic,graphDigest: graph,graphClosureComplete: complete,contextDigest: inventory.contextDigest,dependencyStatus: inventory.metadata["dependencyStatus"] ?? "unknown",entityCount: inventory.entities.count,factCount: inventory.facts.count,fileCount: inventory.inputs.count,byteCount: total)
    }
}
