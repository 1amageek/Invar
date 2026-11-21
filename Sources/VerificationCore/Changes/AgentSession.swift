import Foundation

public struct AgentSession: Codable, Sendable, Equatable {
    public let id: String
    public let principal: String
    public let agentLabel: String?
    public let grants: [String]
    public let policyRevision: Int
    public let expiresAt: Double
    public init(id: String, principal: String, agentLabel: String?, grants: [String], policyRevision: Int, expiresAt: Double) {
        self.id = id
        self.principal = principal
        self.agentLabel = agentLabel
        self.grants = grants
        self.policyRevision = policyRevision
        self.expiresAt = expiresAt
    }
}
