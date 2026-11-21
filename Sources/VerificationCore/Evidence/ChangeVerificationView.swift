import Foundation

public struct ChangeVerificationView: Codable, Sendable, Equatable {
    public let workspaceID: String
    public let changeRevisionID: String?
    public let input: VerificationInput
    public let daemonEpoch: String
    public let sourceRevision: Int
    public let sequence: Int
    public let delta: ObservedDelta?
    public let impactEntityIDs: [String]
    public let unknownBoundaries: [String]
    public let planIDs: [String]
    public let runIDs: [String]
    public let evidenceIDs: [String]
    public let associations: [EvidenceAssociation]
    public let pendingDemandIDs: [String]
    public let diagnostics: [String]
    public init(workspaceID: String, changeRevisionID: String?, input: VerificationInput, daemonEpoch: String, sourceRevision: Int = 0, sequence: Int, delta: ObservedDelta?, impactEntityIDs: [String], unknownBoundaries: [String], planIDs: [String], runIDs: [String], evidenceIDs: [String], associations: [EvidenceAssociation], pendingDemandIDs: [String], diagnostics: [String]) {
        self.workspaceID = workspaceID
        self.changeRevisionID = changeRevisionID
        self.input = input
        self.daemonEpoch = daemonEpoch
        self.sourceRevision = sourceRevision
        self.sequence = sequence
        self.delta = delta
        self.impactEntityIDs = impactEntityIDs
        self.unknownBoundaries = unknownBoundaries
        self.planIDs = planIDs
        self.runIDs = runIDs
        self.evidenceIDs = evidenceIDs
        self.associations = associations
        self.pendingDemandIDs = pendingDemandIDs
        self.diagnostics = diagnostics
    }
    public func reference() throws -> ViewReference {
        let bytes = try Canonical.encode(self)
        let digest = Canonical.digest(bytes)
        return ViewReference(id: digest,sha256: digest,workspaceID: workspaceID,changeRevisionID: changeRevisionID,inputID: input.id,sequence: sequence,daemonEpoch: daemonEpoch)
    }
}
