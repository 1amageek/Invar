public struct ClientSessionGrant: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let workspaceID: String
    public let epoch: String
    public let engineIdentity: String
    public let session: AgentSession
    public let credential: String
    public let resumeCredential: String
    public init(workspaceID: String,epoch: String,engineIdentity: String,session: AgentSession,credential: String,resumeCredential: String) {
        protocolVersion = 2; self.workspaceID = workspaceID; self.epoch = epoch; self.engineIdentity = engineIdentity
        self.session = session; self.credential = credential; self.resumeCredential = resumeCredential
    }
}
