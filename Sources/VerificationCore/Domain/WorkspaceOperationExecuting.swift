public protocol WorkspaceOperationExecuting: Sendable {
    func execute(_ demand: RunDemand,authority: OperationAuthority) async throws -> String
}
