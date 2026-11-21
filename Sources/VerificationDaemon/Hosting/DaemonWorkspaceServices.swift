import VerificationCore

public protocol DaemonWorkspaceServices: WorkspaceOperationExecuting, InputApplicabilityChecking {
    func start() async throws -> DaemonSourceStatus
    func sourceStatus() async -> DaemonSourceStatus
    func closeAdmission() async
    func shutdown() async throws
}
