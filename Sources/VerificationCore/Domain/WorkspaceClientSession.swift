public protocol WorkspaceClientSession: Sendable {
    func refreshSession() async throws -> AgentSession
    func session() async throws -> AgentSession
    func resumeCredential() async throws -> String
    func shutdown() async
}
