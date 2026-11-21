public protocol DaemonAdministrating: Sendable {
    func endpoint() async throws -> LocalDaemonEndpoint
    func status() async throws -> DaemonStatus
    func stop(mode: DaemonStopMode,deadlineSeconds: Double) async throws -> DaemonStatus
    func applyPolicy(_ policy: WorkspacePolicy,expectedRevision: Int) async throws -> DaemonStatus
    func shutdown() async
}
