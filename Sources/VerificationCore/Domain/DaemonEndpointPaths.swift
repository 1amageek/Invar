import Foundation

public struct DaemonEndpointPaths: Sendable, Equatable {
    public let workspaceID: String
    public let userID: UInt32
    public let stateDirectory: URL
    public let runtimeDirectory: URL
    public var controlSocket: URL { runtimeDirectory.appendingPathComponent("control.sock") }
    public var dataSocket: URL { runtimeDirectory.appendingPathComponent("data.sock") }
    public var ownershipLock: URL { runtimeDirectory.appendingPathComponent("owner.lock") }
    public var hostControlRecord: URL { runtimeDirectory.appendingPathComponent("host-control.json") }
    public var stopLatch: URL { stateDirectory.appendingPathComponent("user-stopped") }
    public init(workspaceID: String,userID: UInt32,homeDirectory: URL,stateDirectory: URL? = nil) {
        self.workspaceID = workspaceID; self.userID = userID
        self.stateDirectory = stateDirectory ?? homeDirectory.appendingPathComponent("Library/Application Support/Invar/" + workspaceID)
        runtimeDirectory = URL(fileURLWithPath: "/tmp/invar-" + String(userID) + "-" + workspaceID.suffix(24))
    }
}
