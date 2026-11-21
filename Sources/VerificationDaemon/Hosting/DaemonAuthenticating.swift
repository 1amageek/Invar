import ArchitectureCore
import VerificationCore

public protocol DaemonAuthenticating: WorkspaceAuthorizationChecking {
    func open(peer: ConnectionPeer,label: String?,requested: Set<WorkspaceCapability>,resumeCredential: String?) async throws -> ClientSessionGrant
    func authenticate(credential: String,epoch: String,peer: ConnectionPeer) async throws -> AuthenticatedSession
    func invalidate() async
    func shutdown() async
}
