public struct DaemonStatus: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let workspaceID: String
    public let epoch: String
    public let engineIdentity: String
    public let state: String
    public let activeOperations: Int
    public let watchCount: Int
    public let diagnostics: [String]
    public init(workspaceID: String,epoch: String,engineIdentity: String,state: String,activeOperations: Int,watchCount: Int,diagnostics: [String]) {
        protocolVersion = 3; self.workspaceID = workspaceID; self.epoch = epoch; self.engineIdentity = engineIdentity
        self.state = state; self.activeOperations = activeOperations; self.watchCount = watchCount; self.diagnostics = diagnostics
    }
}
