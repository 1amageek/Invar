import ArchitectureCore
import Darwin
import Foundation
import VerificationClient
import VerificationCore

struct ClientConnection {
    let options: CommandOptions
    func connect() async throws -> LocalVerificationClient {
        let workspace = try WorkspacePaths(options.workspace.path)
        let paths = DaemonEndpointPaths(workspaceID: workspace.workspaceID,userID: getuid(),homeDirectory: FileManager.default.homeDirectoryForCurrentUser,stateDirectory: options.values["state"].map { URL(fileURLWithPath: $0) })
        let admin = LocalDaemonAdministration(paths: paths)
        defer { await admin.shutdown() }
        let endpoint = try await admin.endpoint()
        let directory = options.values["client-state"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".invar-clients")
        let profile = try LocalClientProfile(directory: directory,profile: options.values["client-profile"] ?? "default",workspace: options.workspace,workspaceID: workspace.workspaceID,daemonState: paths.stateDirectory)
        let capabilities = try options.capabilities()
        return try await profile.connect(endpoint: endpoint,label: "invar " + options.command,capabilities: capabilities)
    }
}
