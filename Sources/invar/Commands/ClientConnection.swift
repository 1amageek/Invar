import ArchitectureCore
import Darwin
import Foundation
import VerificationClient
import VerificationCore
import VerificationDaemon

struct ClientConnection {
    let options: CommandOptions
    func connect() async throws -> LocalVerificationClient {
        let workspace = try WorkspacePaths(options.workspace.path)
        let selectedState = options.values["state"].map { URL(fileURLWithPath: $0) }
        let state = try selectedState.map { try DaemonPathValidation.stateRoot($0, outside: workspace.root) }
        let paths = DaemonEndpointPaths(workspaceID: workspace.workspaceID,userID: getuid(),homeDirectory: FileManager.default.homeDirectoryForCurrentUser,stateDirectory: state)
        let admin = LocalDaemonAdministration(paths: paths)
        defer { await admin.shutdown() }
        let endpoint = try await admin.endpoint()
        return try await LocalVerificationClient.connect(endpoint: endpoint)
    }
}
