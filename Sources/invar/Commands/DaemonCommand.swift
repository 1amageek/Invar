import ArchitectureCore
import ArchitectureExtensions
import Darwin
import Foundation
import VerificationBackends
import VerificationClient
import VerificationCore
import VerificationDaemon

struct DaemonCommand {
    let action: String
    let values: [String:String]
    init(_ arguments: [String]) throws {
        guard let action = arguments.first, ["serve","start","status","stop","identity"].contains(action) else { throw InvarError("INVALID_ARGUMENT","Expected daemon serve/start/status/stop/identity",exitCode: 2) }
        self.action = action
        var allowed: Set<String> = ["workspace","state","contracts","mode","deadline"]
        if action == "serve" { allowed.insert("automatic") }
        var values: [String:String] = [:], index = 1
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), allowed.contains(String(key.dropFirst(2))), index+1 < arguments.count, !arguments[index+1].hasPrefix("--"), values[String(key.dropFirst(2))] == nil else { throw InvarError("INVALID_ARGUMENT","Unknown/repeated/missing daemon option",exitCode: 2) }
            values[String(key.dropFirst(2))] = arguments[index+1]; index += 2
        }
        self.values = values
    }
    func execute(workspace: URL? = nil) async throws -> Data {
        let executable = try InvarApp.executableURL()
        let workspace = try workspace ?? WorkspaceSelection.resolve(values["workspace"])
        let configuration = try DaemonConfiguration(workspace: workspace,executable: executable,stateDirectory: values["state"].map { URL(fileURLWithPath: $0) },explicitStart: values["automatic"] == nil,defaultConfigurationPath: values["contracts"])
        let admin = LocalDaemonAdministration(paths: configuration.paths)
        defer { await admin.shutdown() }
        switch action {
        case "identity":
            let peer = try ConnectionPeer.current(), engine = try ExecutionIdentity.current(executable: executable)
            return try Canonical.encode(["schemaVersion":"2","workspaceID":configuration.paths.workspaceID,"engineIdentity":engine,"clientBinaryDigest":peer.binaryDigest,"clientCodeIdentity":peer.codeIdentity,"stateDirectory":configuration.paths.stateDirectory.path])
        case "serve":
            let manifest = InvarProviderManifest.value
            try await WorkspaceDaemon(servicesBuilder: ExplorerServicesBuilder(manifest: manifest)).serve(configuration)
            return try CanonicalJSON.encode(JSONValue.object(["schemaVersion":.number(2),"stopped":.bool(true)]))
        case "start":
            let engine = try ExecutionIdentity.current(executable: executable)
            return try Canonical.encode(try await DaemonLauncher().start(configuration: configuration,engineIdentity: engine))
        case "status": return try Canonical.encode(try await admin.status())
        case "stop":
            let mode: DaemonStopMode
            if let text = values["mode"] { guard let value = DaemonStopMode(rawValue: text) else { throw InvarError("INVALID_ARGUMENT","Stop mode is drain or cancel",exitCode: 2) }; mode = value } else { mode = .drain }
            let deadline: Double
            if let text = values["deadline"] { guard let seconds = Double(text), seconds.isFinite else { throw InvarError("INVALID_ARGUMENT","Stop deadline must be numeric",exitCode: 2) }; deadline = seconds } else { deadline = 30 }
            _ = try await admin.stop(mode: mode,deadlineSeconds: deadline)
            try await waitForStop(configuration.paths,seconds: deadline+10)
            return try CanonicalJSON.encode(JSONValue.object(["schemaVersion":.number(2),"stopped":.bool(true)]))
        default: throw InvarError("INVALID_ARGUMENT","Unknown daemon operation",exitCode: 2)
        }
    }
    private func waitForStop(_ paths: DaemonEndpointPaths,seconds: Double) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let descriptor = open(paths.ownershipLock.path,O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw InvarError("OWNERSHIP_FAILED","Cannot verify daemon ownership release") }
            let acquired = flock(descriptor,LOCK_EX | LOCK_NB) == 0
            if acquired {
                let result = flock(descriptor,LOCK_UN), closed = Darwin.close(descriptor)
                guard result == 0, closed == 0, !FileManager.default.fileExists(atPath: paths.hostControlRecord.path), !FileManager.default.fileExists(atPath: paths.controlSocket.path) else { throw InvarError("RECOVERY_BLOCKED","Owner released without complete control-plane cleanup",exitCode: 6) }
                return
            }
            guard Darwin.close(descriptor) == 0 else { throw InvarError("CLEANUP_FAILED","Ownership probe could not close") }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw InvarError("RECOVERY_BLOCKED","Daemon has not completed its stop/ownership release",exitCode: 6)
    }
}
