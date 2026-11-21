public protocol WorkspaceCoordinating: Sendable {
    func submitWatch(watchID: String,operation: WorkspaceOperation) async throws -> OperationReceipt
    func submit(_ envelope: RequestEnvelope,operation: WorkspaceOperation) async throws -> OperationReceipt
    func status(_ id: String,principal: String,administrative: Bool) async throws -> RunDemand
    func cancel(_ id: String,principal: String,administrative: Bool) async throws
    func recover() async throws
    var activeCount: Int { get async }
    func openAdmission() async throws
    func closeAdmission() async
    func shutdown() async throws
}
