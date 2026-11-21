public protocol VerificationRunningClient: Sendable {
    func verify(planID: String,changeRevisionID: String?,replayOfRunID: String?,key: String,timeout: Double) async throws -> OperationReceipt
    func cancel(operationID: String,key: String,timeout: Double) async throws -> OperationReceipt
    func run(_ id: String) async throws -> VerificationRunSummary
    func replay(_ runID: String) async throws -> ReplayComparison?
}
