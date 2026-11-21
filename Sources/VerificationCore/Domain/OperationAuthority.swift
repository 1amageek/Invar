public struct OperationAuthority: Sendable, Equatable {
    public let principal: String
    public let policyRevision: Int
    public let capabilities: Set<WorkspaceCapability>
    public init(principal: String,policyRevision: Int,capabilities: Set<WorkspaceCapability>) {
        self.principal = principal; self.policyRevision = policyRevision; self.capabilities = capabilities
    }
}
