import ArchitectureCore
import ArchitectureExtensions
import Foundation
import VerificationCore
import VerificationExplorer

@main struct ConnectionFailureMain {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count == 2 else { throw InvarError("INVALID_ARGUMENT","Expected workspace and private fixture directory") }
            let paths = try WorkspacePaths(arguments[0])
            let state = URL(fileURLWithPath: arguments[1])
            let manifest = ExtensionManifest(extensionID: "invar-cleanup",displayName: "Invar cleanup fixture",version: "1.0.0",requestedPermissions: [.graphRead,.inputsRead])
            let connection = try ExplorerProviderConnection(workspace: paths.root.path,stateDirectory: state,manifest: manifest)
            // Registration succeeds, then credential publication must fail on this directory.
            try FileManager.default.createDirectory(at: state.appendingPathComponent("explorer-resume.json"),withIntermediateDirectories: false)
            _ = try await connection.start()
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            var failed = false
            while ContinuousClock.now < deadline {
                let status = await connection.status()
                if status.failure?.code == "SOURCE_OFFLINE", status.failure?.message.contains("explorer-resume.json") == true { failed = true; break }
                try await Task.sleep(for: .milliseconds(25))
            }
            try await connection.shutdown()
            guard failed else { throw InvarError("TEST_DEADLINE","Credential persistence did not reach its failure branch") }
            var bytes = try CanonicalJSON.encode(JSONValue.object(["observedFailure":.bool(true)])); bytes.append(10)
            FileHandle.standardOutput.write(bytes)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}
