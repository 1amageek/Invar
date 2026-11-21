public protocol WorkspaceAuthorizationChecking: Sendable {
    func authority(principal: String,operation: WorkspaceOperation,policyRevision: Int,capabilityCeiling: Set<WorkspaceCapability>?) async throws -> OperationAuthority
}
