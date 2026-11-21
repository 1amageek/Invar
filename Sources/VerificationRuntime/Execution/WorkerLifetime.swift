import Darwin
import Foundation
import VerificationCore

public enum WorkerLifetime {
    private struct Identity: Codable {
        let pid: Int32
        let parentPID: Int32
        let startSeconds: UInt64
        let startMicroseconds: UInt64
    }
    public static func supervise<Value: Sendable>(output: URL, parentPID: Int32, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let pid = getpid()
        guard parentPID > 1, getppid() == parentPID, getpgrp() == pid else { throw InvarError("WORKER_OWNER_LOST", "Worker has no matching coordinator/group owner", exitCode: 6) }
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { throw InvarError("WORKER_OWNER_LOST", "Cannot establish worker identity", exitCode: 6) }
        let identity = Identity(pid: pid, parentPID: parentPID, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
        let marker = output.appendingPathComponent("worker-identity.json")
        try Canonical.encode(identity).write(to: marker, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        let handle = try FileHandle(forWritingTo: marker)
        do { try handle.synchronize(); try handle.close() }
        catch { do { try handle.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED", "Identity sync failed (\(error)); close failed (\(cleanup))") }; throw error }
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                while true {
                    try await Task.sleep(for: .milliseconds(100))
                    if getppid() != parentPID {
                        // This process is the verified leader of its exclusively owned worker group.
                        // Killing the group also stops inherited Lean/Java children after coordinator loss.
                        kill(-pid, SIGKILL)
                        throw InvarError("WORKER_OWNER_LOST", "Coordinator exited", exitCode: 6)
                    }
                }
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw InvarError("WORKER_OWNER_LOST", "Worker produced no terminal value", exitCode: 6) }
            return value
        }
    }
    public static func verifyStopped(beneath root: URL) async throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let jobs = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        guard jobs.count <= 500 else { throw InvarError("RECOVERY_BLOCKED", "Interrupted worker inventory exceeds its limit", exitCode: 6) }
        for job in [root] + jobs {
            let marker = job.appendingPathComponent("worker-identity.json")
            guard FileManager.default.fileExists(atPath: marker.path) else { continue }
            let info = try marker.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= 16384, marker.resolvingSymlinksInPath().path == marker.standardizedFileURL.path else { throw InvarError("RECOVERY_BLOCKED", "Unsafe interrupted worker identity", exitCode: 8) }
            let identity = try JSONDecoder().decode(Identity.self, from: Data(contentsOf: marker))
            guard identity.pid > 1 else { throw InvarError("RECOVERY_BLOCKED", "Invalid interrupted process identity", exitCode: 8) }
            let deadline = ContinuousClock.now.advanced(by: .seconds(4))
            while true {
                var members = [pid_t](repeating: 0, count: 1025)
                let count = members.withUnsafeMutableBytes { proc_listpgrppids(identity.pid, $0.baseAddress, Int32($0.count)) }
                guard count >= 0, count < 1025 else { throw InvarError("RECOVERY_BLOCKED", "Cannot inspect interrupted worker group", exitCode: 6) }
                if count == 0 { break }
                var current = proc_bsdinfo()
                let result = proc_pidinfo(identity.pid, PROC_PIDTBSDINFO, 0, &current, Int32(MemoryLayout<proc_bsdinfo>.size))
                if result == MemoryLayout<proc_bsdinfo>.size {
                    guard current.pbi_start_tvsec == identity.startSeconds, current.pbi_start_tvusec == identity.startMicroseconds,
                        current.pbi_uid == getuid(), current.pbi_pgid == UInt32(identity.pid) else { throw InvarError("RECOVERY_BLOCKED", "Interrupted PID no longer identifies the owned worker", exitCode: 8) }
                    kill(-identity.pid, SIGKILL)
                }
                guard ContinuousClock.now < deadline else { throw InvarError("RECOVERY_BLOCKED", "Interrupted worker group has not stopped; replacement admission refused", exitCode: 6) }
                try await Task.sleep(for: .milliseconds(25))
            }
        }
    }
}
