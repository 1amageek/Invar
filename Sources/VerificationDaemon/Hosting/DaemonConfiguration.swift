import ArchitectureCore
import Darwin
import Foundation
import VerificationCore
import VerificationFormal
import VerificationRuntime

public struct DaemonConfiguration: Sendable {
    public let workspace: URL
    public let paths: DaemonEndpointPaths
    public let executable: URL
    public let storePolicy: StorePolicy
    public let schedulingPolicy: SchedulingPolicy
    public let watchPolicy: WatchPolicy
    public let formalReadPolicy: FormalReadPolicy
    public let maximumDemands: Int
    public let controlConnections: Int
    public let dataConnections: Int
    public let defaultConfigurationPath: String?
    public let explicitStart: Bool
    public init(workspace: URL,executable: URL,stateDirectory: URL? = nil,storePolicy: StorePolicy = .development,schedulingPolicy: SchedulingPolicy = .development,maximumDemands: Int = 32,controlConnections: Int = 2,dataConnections: Int = 2,explicitStart: Bool = true,defaultConfigurationPath: String? = nil,formalReadPolicy: FormalReadPolicy = .development,watchPolicy: WatchPolicy = .development) throws {
        let root = try DaemonPathValidation.canonical(workspace)
        let workspacePaths = try WorkspacePaths(root.path)
        let selected = DaemonEndpointPaths(workspaceID: workspacePaths.workspaceID,userID: getuid(),homeDirectory: FileManager.default.homeDirectoryForCurrentUser,stateDirectory: stateDirectory)
        let state = try DaemonPathValidation.stateRoot(selected.stateDirectory,outside: root)
        self.workspace = root; self.executable = executable.standardizedFileURL
        paths = DaemonEndpointPaths(workspaceID: workspacePaths.workspaceID,userID: getuid(),homeDirectory: FileManager.default.homeDirectoryForCurrentUser,stateDirectory: state)
        try watchPolicy.validate(); self.watchPolicy = watchPolicy
        try formalReadPolicy.validate(); self.formalReadPolicy = formalReadPolicy
        self.storePolicy = storePolicy; self.schedulingPolicy = schedulingPolicy
        if let defaultConfigurationPath { _ = try Canonical.relative(defaultConfigurationPath) }
        self.defaultConfigurationPath = defaultConfigurationPath
        self.maximumDemands = maximumDemands; self.controlConnections = controlConnections; self.dataConnections = dataConnections; self.explicitStart = explicitStart
        try storePolicy.validate(); try schedulingPolicy.validate()
        guard (1...storePolicy.maximumReservations).contains(maximumDemands), (1...32).contains(controlConnections), (1...32).contains(dataConnections) else { throw InvarError("INVALID_POLICY","Host admission/connection budget is invalid") }
    }
}
