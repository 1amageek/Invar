import Foundation

public struct ViewReference: Codable, Sendable, Equatable {
    public let id: String
    public let sha256: String
    public let workspaceID: String
    public let changeRevisionID: String?
    public let inputID: String
    public let sequence: Int
    public let daemonEpoch: String
    public init(id: String, sha256: String, workspaceID: String, changeRevisionID: String?, inputID: String, sequence: Int, daemonEpoch: String) {
        self.id = id
        self.sha256 = sha256
        self.workspaceID = workspaceID
        self.changeRevisionID = changeRevisionID
        self.inputID = inputID
        self.sequence = sequence
        self.daemonEpoch = daemonEpoch
    }
}
