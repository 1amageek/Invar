import VerificationCore

protocol DaemonHostControlling: Sendable {
    func administrativeStatus() async throws -> DaemonStatus
    func requestStop(mode: DaemonStopMode,deadlineSeconds: Double,requestID: String) async throws -> DaemonStatus
    func stopResponseFinished(requestID: String) async
}
