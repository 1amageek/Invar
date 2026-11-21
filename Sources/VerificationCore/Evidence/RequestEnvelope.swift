import Foundation

public struct RequestEnvelope: Codable, Sendable, Equatable {
    public let id: String
    public let sessionID: String?
    public let watchID: String?
    public var hasCapabilityCeiling: Bool { sessionID != nil || watchID != nil }
    public let capabilities: [WorkspaceCapability]
    public let requestKey: String
    public let principal: String
    public let workspaceID: String
    public let fingerprint: String
    public let operation: String
    public let daemonEpoch: String
    public let policyRevision: Int
    public let expiresAt: Double
    public let retainUntil: Double
    public init(id: String, sessionID: String? = nil, watchID: String? = nil, capabilities: [WorkspaceCapability] = [], requestKey: String, principal: String, workspaceID: String, fingerprint: String, operation: String, daemonEpoch: String, policyRevision: Int, expiresAt: Double, retainUntil: Double) {
        self.id = id
        self.sessionID = sessionID; self.watchID = watchID; self.capabilities = capabilities.sorted { $0.rawValue < $1.rawValue }
        self.requestKey = requestKey
        self.principal = principal
        self.workspaceID = workspaceID
        self.fingerprint = fingerprint
        self.operation = operation
        self.daemonEpoch = daemonEpoch
        self.policyRevision = policyRevision
        self.expiresAt = expiresAt
        self.retainUntil = retainUntil
    }
}
