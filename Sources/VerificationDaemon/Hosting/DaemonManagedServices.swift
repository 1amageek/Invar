import VerificationCore

public protocol DaemonManagedServices: Sendable {
    func bind(coordinator: any WorkspaceCoordinating,authentication: any DaemonAuthenticating) async throws
    func activate() async throws
}
