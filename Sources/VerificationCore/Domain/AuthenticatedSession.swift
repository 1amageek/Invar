public struct AuthenticatedSession: Sendable, Equatable {
    public let session: AgentSession
    public let authority: OperationAuthority
    public init(session: AgentSession,authority: OperationAuthority) { self.session = session; self.authority = authority }
}
