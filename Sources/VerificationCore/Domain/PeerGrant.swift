public struct PeerGrant: Codable, Sendable, Equatable {
    public let binaryDigest: String
    public let capabilities: [WorkspaceCapability]
    public init(binaryDigest: String,capabilities: Set<WorkspaceCapability>) {
        self.binaryDigest = binaryDigest; self.capabilities = capabilities.sorted { $0.rawValue < $1.rawValue }
    }
}
