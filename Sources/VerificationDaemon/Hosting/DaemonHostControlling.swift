import VerificationCore

protocol DaemonHostControlling: Sendable {
    func administrativeStatus() async throws -> DaemonStatus
    func requestStop(mode: DaemonStopMode,deadlineSeconds: Double,requestID: String) async throws -> DaemonStatus
    func stopResponseFinished(requestID: String) async
    func installPolicy(_ policy: WorkspacePolicy,expectedRevision: Int) async throws -> DaemonStatus
}
