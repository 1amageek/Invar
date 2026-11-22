import Foundation

public struct RequestEnvelope: Codable, Sendable, Equatable {
    public let id: String
    public let watchID: String?
    public let requestKey: String
    public let principal: String
    public let workspaceID: String
    public let fingerprint: String
    public let operation: String
    public let daemonEpoch: String
    public let expiresAt: Double
    public let retainUntil: Double
    public init(id: String, watchID: String? = nil, requestKey: String, principal: String, workspaceID: String, fingerprint: String, operation: String, daemonEpoch: String, expiresAt: Double, retainUntil: Double) {
        self.id = id
        self.watchID = watchID
        self.requestKey = requestKey
        self.principal = principal
        self.workspaceID = workspaceID
        self.fingerprint = fingerprint
        self.operation = operation
        self.daemonEpoch = daemonEpoch
        self.expiresAt = expiresAt
        self.retainUntil = retainUntil
    }
}
