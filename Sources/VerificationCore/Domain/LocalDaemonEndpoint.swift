import Foundation

public struct LocalDaemonEndpoint: Codable, Sendable, Equatable {
    public let workspaceID: String
    public let socketPath: String
    public let dataSocketPath: String
    public let serverBinaryDigest: String
    public let serverCodeIdentity: String
    public let engineIdentity: String
    public init(workspaceID: String,socketPath: String,dataSocketPath: String? = nil,serverBinaryDigest: String,serverCodeIdentity: String,engineIdentity: String) {
        self.workspaceID = workspaceID; self.socketPath = socketPath; self.dataSocketPath = dataSocketPath ?? socketPath; self.serverBinaryDigest = serverBinaryDigest; self.serverCodeIdentity = serverCodeIdentity; self.engineIdentity = engineIdentity
    }
}
