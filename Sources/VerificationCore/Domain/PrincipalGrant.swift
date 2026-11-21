public struct PrincipalGrant: Codable, Sendable, Equatable {
    public let credentialDigest: String
    public let principal: String
    public let workspaceID: String
    public let binaryDigest: String
    public let codeIdentity: String
    public let initialAuditDigest: String
    public let capabilities: [WorkspaceCapability]
    public let policyRevision: Int
    public let expiresAt: Double
    public init(credentialDigest: String,principal: String,workspaceID: String,binaryDigest: String,codeIdentity: String,initialAuditDigest: String,capabilities: Set<WorkspaceCapability>,policyRevision: Int,expiresAt: Double) {
        self.credentialDigest = credentialDigest; self.principal = principal; self.workspaceID = workspaceID; self.binaryDigest = binaryDigest
        self.codeIdentity = codeIdentity; self.initialAuditDigest = initialAuditDigest; self.capabilities = capabilities.sorted { $0.rawValue < $1.rawValue }
        self.policyRevision = policyRevision; self.expiresAt = expiresAt
    }
}
