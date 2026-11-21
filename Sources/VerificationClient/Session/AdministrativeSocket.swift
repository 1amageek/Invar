import ArchitectureCore
import Darwin
import Foundation
import VerificationCore

enum AdministrativeSocket {
    static func connect(path: String,record: DaemonHostRecord) async throws -> LocalConnection {
        let descriptor = try LocalSocket.create()
        do {
            let result = try address(path) { Darwin.connect(descriptor,$0,$1) }
            guard result == 0 || errno == EINPROGRESS else { throw InvarError("DAEMON_UNAVAILABLE","Administrative socket is unavailable",exitCode: 6) }
            if result != 0 {
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while true {
                    try Task.checkCancellation()
                    var status = pollfd(fd: descriptor,events: Int16(POLLOUT),revents: 0)
                    let ready = Darwin.poll(&status,1,0)
                    if ready > 0 {
                        var error: Int32 = 0, count = socklen_t(MemoryLayout<Int32>.size)
                        guard getsockopt(descriptor,SOL_SOCKET,SO_ERROR,&error,&count) == 0, error == 0 else { throw InvarError("DAEMON_UNAVAILABLE","Administrative connection was rejected",exitCode: 6) }
                        break
                    }
                    guard ready >= 0 || errno == EINTR, ContinuousClock.now < deadline else { throw InvarError("TIMEOUT","Administrative connection did not become ready",exitCode: 6) }
                    try await Task.sleep(for: .milliseconds(5))
                }
            }
            try authenticate(descriptor,record: record)
            // Descriptor ownership moves once into the shared frame transport.
            // That transport still checks UID and owns close/shutdown. Its
            // disk-dependent code lookup is not used for private host control.
            return try LocalConnection(descriptor: descriptor)
        } catch {
            guard Darwin.close(descriptor) == 0 else { throw InvarError("CLEANUP_FAILED","Administrative connect failed (\(error)); descriptor close failed") }
            throw error
        }
    }
    private static func authenticate(_ descriptor: Int32,record: DaemonHostRecord) throws {
        var user: uid_t = 0, group: gid_t = 0, pid: Int32 = 0
        var pidCount = socklen_t(MemoryLayout<Int32>.size), auditCount = socklen_t(32)
        var token = [UInt32](repeating: 0,count: 8)
        let status = token.withUnsafeMutableBytes { bytes in getsockopt(descriptor,SOL_LOCAL,LOCAL_PEERTOKEN,bytes.baseAddress,&auditCount) }
        let audit = token.withUnsafeBytes { Data($0).base64EncodedString() }
        var birth = proc_bsdinfo()
        guard getpeereid(descriptor,&user,&group) == 0, user == getuid(),
            status == 0, auditCount == 32, audit == record.auditIdentity,
            getsockopt(descriptor,SOL_LOCAL,LOCAL_PEERPID,&pid,&pidCount) == 0, pid == record.processID,
            proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&birth,Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
            birth.pbi_uid == getuid(), birth.pbi_start_tvsec == record.startSeconds, birth.pbi_start_tvusec == record.startMicroseconds else { throw InvarError("AUTHENTICATION_REQUIRED","Socket differs from the original kernel host identity",exitCode: 8) }
    }
    private static func address<Value>(_ path: String,_ body: (UnsafePointer<sockaddr>,socklen_t) throws -> Value) throws -> Value {
        var address = sockaddr_un()
        let bytes = Array(path.utf8), capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity, !bytes.contains(0) else { throw InvarError("INVALID_ARGUMENT","Invalid administrative socket path") }
        address.sun_family = sa_family_t(AF_UNIX); address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        // A zero-initialized stack sockaddr owns a bounded NUL-terminated path.
        // Rebinding lasts only for this syscall closure; no pointer escapes.
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self,repeating: 0); buffer.copyBytes(from: bytes)
        }
        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self,capacity: 1) { try body($0,socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }
}
