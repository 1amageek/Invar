import VerificationCore

public protocol ClientProfileConnecting: Sendable {
    func connect(endpoint: LocalDaemonEndpoint,label: String?,capabilities: Set<WorkspaceCapability>) async throws -> LocalVerificationClient
}
