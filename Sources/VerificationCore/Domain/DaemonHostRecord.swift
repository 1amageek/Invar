import Foundation

public struct DaemonHostRecord: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let stateDirectory: String
    public let epoch: String
    public let endpoint: LocalDaemonEndpoint
    public let auditIdentity: String
    public let processID: Int32
    public let startSeconds: UInt64
    public let startMicroseconds: UInt64
    public let administrativeCredential: String
    public init(stateDirectory: String,epoch: String,endpoint: LocalDaemonEndpoint,auditIdentity: String,processID: Int32,startSeconds: UInt64,startMicroseconds: UInt64,administrativeCredential: String) {
        schemaVersion = 2; self.stateDirectory = stateDirectory; self.epoch = epoch; self.endpoint = endpoint; self.auditIdentity = auditIdentity; self.processID = processID
        self.startSeconds = startSeconds; self.startMicroseconds = startMicroseconds; self.administrativeCredential = administrativeCredential
    }
}
