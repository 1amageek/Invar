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
        guard let action = arguments.first, ["serve","start","status","stop","approve","identity"].contains(action) else { throw InvarError("INVALID_ARGUMENT","Expected daemon serve/start/status/stop/approve/identity",exitCode: 2) }
        self.action = action
        let allowed: Set<String> = ["workspace","state","policy","contracts","mode","deadline"]
        var values: [String:String] = [:], index = 1
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), allowed.contains(String(key.dropFirst(2))), index+1 < arguments.count, !arguments[index+1].hasPrefix("--"), values[String(key.dropFirst(2))] == nil else { throw InvarError("INVALID_ARGUMENT","Unknown/repeated/missing daemon option",exitCode: 2) }
            values[String(key.dropFirst(2))] = arguments[index+1]; index += 2
        }
        self.values = values
    }
    func execute() async throws -> Data {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let workspace = URL(fileURLWithPath: values["workspace"] ?? FileManager.default.currentDirectoryPath)
        let policy: WorkspacePolicy?
        if ["serve","start","approve"].contains(action), let path = values["policy"] { policy = try readPolicy(URL(fileURLWithPath: path)) } else { policy = nil }
        let configuration = try DaemonConfiguration(workspace: workspace,executable: executable,stateDirectory: values["state"].map { URL(fileURLWithPath: $0) },initialPolicy: action == "approve" ? nil : policy,defaultConfigurationPath: values["contracts"])
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
            return try Canonical.encode(try await DaemonLauncher().start(configuration: configuration,engineIdentity: engine,policyPath: values["policy"]))
        case "status": return try Canonical.encode(try await admin.status())
        case "stop":
            let mode: DaemonStopMode
            if let text = values["mode"] { guard let value = DaemonStopMode(rawValue: text) else { throw InvarError("INVALID_ARGUMENT","Stop mode is drain or cancel",exitCode: 2) }; mode = value } else { mode = .drain }
            let deadline: Double
            if let text = values["deadline"] { guard let seconds = Double(text), seconds.isFinite else { throw InvarError("INVALID_ARGUMENT","Stop deadline must be numeric",exitCode: 2) }; deadline = seconds } else { deadline = 30 }
            _ = try await admin.stop(mode: mode,deadlineSeconds: deadline)
            try await waitForStop(configuration.paths,seconds: deadline+10)
            return try CanonicalJSON.encode(JSONValue.object(["schemaVersion":.number(2),"stopped":.bool(true)]))
        case "approve":
            guard let policy else { throw InvarError("INVALID_ARGUMENT","daemon approve requires --policy",exitCode: 2) }
            return try Canonical.encode(try await admin.applyPolicy(policy,expectedRevision: policy.revision-1))
        default: throw InvarError("INVALID_ARGUMENT","Unknown daemon operation",exitCode: 2)
        }
    }
    private func readPolicy(_ path: URL) throws -> WorkspacePolicy {
        let attributes = try path.resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true, (attributes.fileSize ?? Int.max) <= 65536 else { throw InvarError("INVALID_POLICY","Expected a bounded regular host policy",exitCode: 2) }
        let handle = try FileHandle(forReadingFrom: path)
        let bytes: Data
        do { bytes = try handle.read(upToCount: 65537) ?? Data(); try handle.close() }
        catch { do { try handle.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED","Policy read failed (\(error)); close failed (\(cleanup))") }; throw error }
        guard bytes.count <= 65536 else { throw InvarError("RESOURCE_LIMIT","Host policy grew beyond its bound",exitCode: 6) }
        let value = try JSONDecoder().decode(WorkspacePolicy.self,from: bytes)
        let canonical = try Canonical.encode(value)
        let parsed = try JSONSerialization.jsonObject(with: bytes) as? NSDictionary, normalized = try JSONSerialization.jsonObject(with: canonical) as? NSDictionary
        guard parsed == normalized else { throw InvarError("INVALID_POLICY","Host policy contains unknown fields",exitCode: 2) }
        return value
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
