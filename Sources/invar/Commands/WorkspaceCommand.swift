import ArchitectureCore
import Foundation
import VerificationBackends
import VerificationClient
import VerificationCore
import VerificationDaemon

struct WorkspaceCommand {
    static func open(_ arguments: [String]) async throws {
        let noOpen = arguments.contains("--no-open")
        let codexBrowser = arguments.contains("--codex-browser")
        let hostFlags = ["--no-open", "--codex-browser"]
        guard arguments.filter({ hostFlags.contains($0) }).count <= 1 else {
            throw InvarError("INVALID_ARGUMENT", "Choose at most one browser mode", exitCode: 2)
        }
        if codexBrowser, ProcessInfo.processInfo.environment["CODEX_THREAD_ID"].flatMap(UUID.init(uuidString:)) == nil {
            throw InvarError("INVALID_ARGUMENT", "--codex-browser requires the originating Codex thread", exitCode: 2)
        }
        let command = try DaemonCommand(["start"] + arguments.filter { !hostFlags.contains($0) })
        let workspace = try WorkspaceSelection.resolve(command.values["workspace"])
        let explorer = try ExplorerHost.locate(workspace: workspace)
        try await explorer.ensureIndex()
        let response = try await command.execute(workspace: workspace)
        let status = try JSONDecoder().decode(DaemonStatus.self, from: response)
        FileHandle.standardError.write(Data("Workspace: \(workspace.path)\nInvar: \(status.state)\n".utf8))
        try await explorer.open(noOpen: noOpen, codexBrowser: codexBrowser)
    }

    static func activateForMCP(_ options: CommandOptions) async throws {
        let configuration = try DaemonConfiguration(workspace: options.workspace, executable: InvarApp.executableURL(),
            stateDirectory: options.values["state"].map { URL(fileURLWithPath: $0) }, explicitStart: false,
            defaultConfigurationPath: options.values["contracts"])
        let admin = LocalDaemonAdministration(paths: configuration.paths)
        defer { await admin.shutdown() }
        do { _ = try await admin.status(); return }
        catch let error as InvarError where error.code == "DAEMON_UNAVAILABLE" {}
        catch let error as ArchitectureError where error.code == "CONNECTION_FAILED" {}
        let engine = try ExecutionIdentity.current(executable: configuration.executable)
        _ = try await DaemonLauncher().start(configuration: configuration,engineIdentity: engine)
        if try await ExplorerHost.isIndexRunning(in: options.workspace) == false {
            try await ExplorerHost.locate(workspace: options.workspace).ensureIndex()
        }
    }
}
