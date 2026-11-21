public protocol WorkspaceRequesting: Sendable {
    func prepare(_ operation: WorkspaceOperation,key: String,timeout: Double) async throws -> PreparedOperation
    func accept(_ prepared: PreparedOperation) async throws -> OperationReceipt
    func receipt(envelopeID: String) async throws -> OperationReceipt?
    func operation(_ id: String) async throws -> RunDemand
}
