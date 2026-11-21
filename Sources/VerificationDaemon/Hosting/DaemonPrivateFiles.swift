import Darwin
import Foundation
import VerificationCore

struct DaemonPrivateFiles {
    let paths: DaemonEndpointPaths
    func prepare(explicitStart: Bool) throws {
        if FileManager.default.fileExists(atPath: paths.stopLatch.path) {
            guard explicitStart else { throw InvarError("USER_STOPPED","Explicit user stop prevents automatic activation",exitCode: 6) }
            try requireOwnedFile(paths.stopLatch)
            guard unlink(paths.stopLatch.path) == 0 else { throw InvarError("IO_FAILURE","Cannot clear explicit-stop latch") }
            try synchronize(paths.stateDirectory)
        }
        for socket in [paths.controlSocket,paths.dataSocket] {
            var info = stat()
            if lstat(socket.path,&info) == 0 {
                guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else { throw InvarError("OWNERSHIP_FAILED","Stale socket path is not an owned socket",exitCode: 8) }
                guard unlink(socket.path) == 0 else { throw InvarError("IO_FAILURE","Cannot retire stale owned socket") }
            } else if errno != ENOENT { throw InvarError("IO_FAILURE","Cannot inspect old socket") }
        }
    }
    func publish(_ record: DaemonHostRecord) throws {
        if FileManager.default.fileExists(atPath: paths.hostControlRecord.path) { try requireOwnedFile(paths.hostControlRecord) }
        let bytes = try Canonical.encode(record)
        guard bytes.count <= 16384 else { throw InvarError("RESOURCE_LIMIT","Private host record exceeds its profile") }
        try write(bytes,to: paths.hostControlRecord)
    }
    func stopLatch() throws { try write(Data("explicit-stop\n".utf8),to: paths.stopLatch) }
    func removeRecord(epoch: String) throws {
        guard FileManager.default.fileExists(atPath: paths.hostControlRecord.path) else { return }
        try requireOwnedFile(paths.hostControlRecord)
        let bytes = try Data(contentsOf: paths.hostControlRecord)
        guard bytes.count <= 16384 else { throw InvarError("OWNERSHIP_FAILED","Host record was replaced") }
        let record = try JSONDecoder().decode(DaemonHostRecord.self,from: bytes)
        guard record.epoch == epoch else { throw InvarError("OWNERSHIP_FAILED","Host-control epoch was replaced") }
        guard unlink(paths.hostControlRecord.path) == 0 else { throw InvarError("CLEANUP_FAILED","Host-control record could not be removed") }
        try synchronize(paths.runtimeDirectory)
    }
    private func requireOwnedFile(_ path: URL) throws {
        var info = stat()
        guard lstat(path.path,&info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_mode & 0o077 == 0, info.st_size <= 16384 else { throw InvarError("OWNERSHIP_FAILED","Unsafe private host file",exitCode: 8) }
    }
    private func write(_ bytes: Data,to path: URL) throws {
        if FileManager.default.fileExists(atPath: path.path) { try requireOwnedFile(path) }
        try bytes.write(to: path,options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],ofItemAtPath: path.path)
        let handle = try FileHandle(forWritingTo: path)
        do { try handle.synchronize(); try handle.close() }
        catch { do { try handle.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED","Private file sync failed (\(error)); close failed (\(cleanup))") }; throw error }
        try synchronize(path.deletingLastPathComponent())
    }
    private func synchronize(_ path: URL) throws {
        let descriptor = open(path.path,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw InvarError("IO_FAILURE","Cannot open private directory for synchronization") }
        let result = fsync(descriptor), closed = Darwin.close(descriptor)
        guard result == 0, closed == 0 else { throw InvarError("IO_FAILURE","Cannot synchronize private directory") }
    }
}
