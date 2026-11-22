import VerificationCore

public protocol DaemonManagedServices: Sendable {
    func bind(coordinator: any WorkspaceCoordinating) async throws
    func activate() async throws
}
