import ArchitectureCore
import Darwin
import Foundation
import VerificationCore

public actor DaemonRPCServer: DaemonRPCServing {
    private let socket: URL
    private let device: dev_t
    private let inode: ino_t
    private let channel: DaemonRPCChannel
    private let maximumConnections: Int
    private let handler: any DaemonRequestHandling
    private var descriptor: Int32
    private var accepting = true
    private var serving = false
    private var tasks: [UUID:Task<Void,Never>] = [:]
    private var shutdownTask: Task<Void,any Error>?
    public init(socket: URL,channel: DaemonRPCChannel,maximumConnections: Int,handler: any DaemonRequestHandling) throws {
        guard (1...32).contains(maximumConnections) else { throw InvarError("INVALID_POLICY","Invalid RPC connection capacity") }
        var parent = stat()
        guard lstat(socket.deletingLastPathComponent().path,&parent) == 0, parent.st_mode & S_IFMT == S_IFDIR, parent.st_uid == getuid(), parent.st_mode & 0o077 == 0 else { throw InvarError("OWNERSHIP_FAILED","RPC parent must be an owned private directory",exitCode: 8) }
        let opened = try LocalSocket.listen(path: socket.path)
        var info = stat()
        guard lstat(socket.path,&info) == 0, info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid() else {
            Darwin.close(opened); throw InvarError("OWNERSHIP_FAILED","RPC socket identity could not be established",exitCode: 8)
        }
        self.socket = socket; descriptor = opened; device = info.st_dev; inode = info.st_ino
        self.channel = channel; self.maximumConnections = maximumConnections; self.handler = handler
    }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
    public var activeConnectionCount: Int { tasks.count }
    public func serve() async throws {
        guard !serving, accepting, descriptor >= 0 else { throw InvarError("DAEMON_STOPPED","RPC listener is already serving or closed") }
        serving = true; defer { serving = false }
        do {
            while accepting && descriptor >= 0 {
                try Task.checkCancellation()
                do {
                    if let connection = try LocalSocket.accept(descriptor) {
                        guard tasks.count < maximumConnections else { await connection.close(); continue }
                        let id = UUID(), handler = self.handler, channel = self.channel
                        tasks[id] = Task {
                            await Self.process(connection,handler: handler,channel: channel)
                            self.finished(id)
                        }
                    }
                } catch let error as ArchitectureError where error.code == "PEER_CONNECTION_REJECTED" { continue }
                try await Task.sleep(for: .milliseconds(5))
            }
            try await shutdown()
        } catch {
            do { try await shutdown() }
            catch let cleanup { throw InvarError("CLEANUP_FAILED","RPC listener failed (\(error)); shutdown failed (\(cleanup))") }
            throw error
        }
    }
    private func finished(_ id: UUID) { tasks.removeValue(forKey: id) }
    private nonisolated static func process(_ connection: LocalConnection,handler: any DaemonRequestHandling,channel: DaemonRPCChannel) async {
        defer { await connection.close() }
        do {
            guard let request = try await connection.read(timeout: .seconds(5)) else { return }
            defer {
                if let observer = handler as? any DaemonResponseObserving { await observer.responseFinished(request) }
            }
            let id = request["id"]
            do {
                let bytes = try CanonicalJSON.encode(request)
                guard bytes.count <= 65_536, let identity = id.string, !identity.isEmpty, identity.utf8.count <= 128 else { throw InvarError("INVALID_REQUEST","RPC request identity/size exceeds typed protocol limits",exitCode: 2) }
                guard let value = try await handler.handle(request,channel: channel) else { return }
                let response: JSONValue = .object(["id":id,"result":value])
                let encoded = try CanonicalJSON.encode(response)
                guard encoded.count <= 1_048_576 else { throw InvarError("RESOURCE_LIMIT","RPC response exceeds its page budget",exitCode: 6) }
                try await connection.write(response,timeout: .seconds(5))
            } catch {
                let typed: InvarError
                if let value = error as? InvarError { typed = value }
                else if let value = error as? ArchitectureError { typed = InvarError(value.code,value.message,exitCode: value.exitCode) }
                else if error is DecodingError { typed = InvarError("INVALID_REQUEST","Malformed typed request",exitCode: 2) }
                else { typed = InvarError(error is CancellationError ? "CANCELLED" : "DAEMON_REQUEST_FAILED",String(describing: error),exitCode: error is CancellationError ? 130 : 7) }
                let bounded = InvarError(typed.code.utf8.count <= 128 ? typed.code : "INVALID_DIAGNOSTIC",String(typed.message.prefix(1024)),exitCode: typed.exitCode)
                let body = try JSONValue.encode(bounded)
                try await connection.write(.object(["id":id,"error":body]),timeout: .seconds(5))
            }
        } catch {
            // A closed local peer loses only this connection. Its
            // transport failure does not cancel any durably accepted operation.
        }
    }
    public func shutdown() async throws {
        if let shutdownTask { try await shutdownTask.value; return }
        accepting = false
        let active = Array(tasks.values)
        let task = Task {
            for connection in active { connection.cancel() }
            for connection in active { await connection.value }
            let owned = descriptor; descriptor = -1
            if owned >= 0, Darwin.close(owned) != 0 { throw InvarError("CLEANUP_FAILED","RPC listener descriptor could not close") }
            var current = stat()
            if lstat(socket.path,&current) == 0 {
                guard current.st_dev == device, current.st_ino == inode, current.st_mode & S_IFMT == S_IFSOCK else { throw InvarError("OWNERSHIP_FAILED","RPC socket was replaced before shutdown",exitCode: 8) }
                guard unlink(socket.path) == 0 else { throw InvarError("CLEANUP_FAILED","Owned RPC socket could not be removed") }
            } else if errno != ENOENT { throw InvarError("CLEANUP_FAILED","Owned RPC socket identity cannot be read") }
        }
        shutdownTask = task
        try await task.value
    }
}
