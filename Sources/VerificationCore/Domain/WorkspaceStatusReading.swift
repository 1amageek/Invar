public protocol WorkspaceStatusReading: Sendable {
    func status() async throws -> DaemonStatus
}
