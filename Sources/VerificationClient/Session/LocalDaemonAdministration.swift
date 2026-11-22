import ArchitectureCore
import Darwin
import Foundation
import VerificationCore

public actor LocalDaemonAdministration: DaemonAdministrating {
    private let paths: DaemonEndpointPaths
    private var closed = false
    private var connections: [UUID:LocalConnection] = [:]
    public init(paths: DaemonEndpointPaths) { self.paths = paths }
    public func endpoint() throws -> LocalDaemonEndpoint { try record().endpoint }
    public func status() async throws -> DaemonStatus { try await exchange("host.status",body: .object([:])) }
    public func stop(mode: DaemonStopMode,deadlineSeconds: Double) async throws -> DaemonStatus {
        guard deadlineSeconds.isFinite, (1...300).contains(deadlineSeconds) else { throw InvarError("INVALID_REQUEST","Stop deadline must be 1...300 seconds") }
        return try await exchange("host.stop",body: .object(["mode":.string(mode.rawValue),"deadlineSeconds":.number(deadlineSeconds)]))
    }
    private func record() throws -> DaemonHostRecord {
        guard !closed else { throw InvarError("SESSION_CLOSED","Administrative client is closed") }
        var parent = stat()
        if lstat(paths.runtimeDirectory.path, &parent) != 0 {
            guard errno == ENOENT else { throw InvarError("AUTHENTICATION_REQUIRED", "Host-control directory cannot be inspected", exitCode: 8) }
            throw InvarError("DAEMON_UNAVAILABLE", "No private host-control directory", exitCode: 6)
        }
        guard parent.st_uid == getuid(), parent.st_mode & S_IFMT == S_IFDIR, parent.st_mode & 0o077 == 0 else {
            throw InvarError("AUTHENTICATION_REQUIRED", "Host-control directory is unsafe", exitCode: 8)
        }
        let descriptor = open(paths.hostControlRecord.path,O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw InvarError("DAEMON_UNAVAILABLE","No private host-control record",exitCode: 6) }
        let handle = FileHandle(fileDescriptor: descriptor,closeOnDealloc: false)
        let bytes: Data
        do {
            var info = stat()
            guard fstat(descriptor,&info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0, info.st_size <= 16384 else { throw InvarError("AUTHENTICATION_REQUIRED","Host-control record is unsafe",exitCode: 8) }
            bytes = try handle.read(upToCount: 16385) ?? Data()
            try handle.close()
        } catch {
            do { try handle.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED","Host record read failed (\(error)); close failed (\(cleanup))") }
            throw error
        }
        guard bytes.count <= 16384 else { throw InvarError("RESOURCE_LIMIT","Host-control record grew beyond its bound") }
        let value = try JSONDecoder().decode(DaemonHostRecord.self,from: bytes)
        guard value.schemaVersion == 2, value.endpoint.workspaceID == paths.workspaceID, value.endpoint.socketPath == paths.controlSocket.path, value.endpoint.dataSocketPath == paths.dataSocket.path,
            value.processID > 1, Data(base64Encoded: value.auditIdentity)?.count == 32 else { throw InvarError("AUTHENTICATION_REQUIRED","Host record workspace/protocol differs",exitCode: 8) }
        guard value.stateDirectory == paths.stateDirectory.path else {
            throw InvarError("WORKSPACE_STATE_MISMATCH", "Use the state directory configured for this workspace daemon", exitCode: 8)
        }
        return value
    }
    private func exchange(_ method: String,body: JSONValue) async throws -> DaemonStatus {
        guard !closed, connections.count < 8 else { throw InvarError("RESOURCE_LIMIT","Administrative client is closed or full",exitCode: 6) }
        let record = try record(), id = UUID()
        let connection = try await AdministrativeSocket.connect(path: paths.controlSocket.path,record: record)
        connections[id] = connection
        defer { connections.removeValue(forKey: id); await connection.close() }
        guard !closed else { throw InvarError("SESSION_CLOSED","Administrative client closed while connecting") }
        let request: JSONValue = .object(["id":.string(id.uuidString),"protocolVersion":.number(3),"workspaceID":.string(paths.workspaceID),"epoch":.string(record.epoch),"method":.string(method),"body":body])
        let bytes = try CanonicalJSON.encode(request)
        guard bytes.count <= 65_536 else { throw InvarError("RESOURCE_LIMIT","Administrative request exceeds typed IPC bound",exitCode: 6) }
        try await connection.write(request,timeout: .seconds(5))
        guard let response = try await connection.read(timeout: .seconds(5)), response["id"].string == id.uuidString else { throw InvarError("UNKNOWN_DELIVERY","No matching administrative acknowledgement",exitCode: 6) }
        if response["error"] != .null { throw try response["error"].decode(InvarError.self) }
        let value = try response["result"].decode(DaemonStatus.self)
        guard value.epoch == record.epoch, value.workspaceID == paths.workspaceID, value.engineIdentity == record.endpoint.engineIdentity else { throw InvarError("PROTOCOL_MISMATCH","Administrative status changed host identity") }
        return value
    }
    public func shutdown() async {
        closed = true
        for connection in connections.values { await connection.close() }
        connections.removeAll()
    }
}
