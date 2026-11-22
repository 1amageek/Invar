public protocol WorkspaceOperationExecuting: Sendable {
    func execute(_ demand: RunDemand) async throws -> String
}
