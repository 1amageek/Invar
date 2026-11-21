public protocol ExternalWorkspaceCoordinating: WorkspaceCoordinating {
    func submitExternal(actionID: String) async throws -> OperationReceipt
}
