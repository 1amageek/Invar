import Darwin
import Foundation
import VerificationCore

/// Owns a private, fixed-scope principal-resume record, never daemon data.
public struct LocalClientProfile: ClientProfileConnecting {
    private struct Record: Codable, Equatable {
        let workspaceID: String
        let profile: String
        let engine: String
        let capabilities: [WorkspaceCapability]
        let credential: String
    }
    private let directory: URL
    private let profile: String
    private let workspaceID: String
    public init(directory: URL,profile: String,workspace: URL,workspaceID: String,daemonState: URL) throws {
        guard !profile.isEmpty, profile.utf8.count <= 128, !workspaceID.isEmpty else { throw InvarError("INVALID_ARGUMENT","Invalid client profile identity") }
        let selected = directory.standardizedFileURL.resolvingSymlinksInPath()
        for root in [workspace,daemonState] {
            let path = root.standardizedFileURL.resolvingSymlinksInPath().path
            guard selected.path != path, !selected.path.hasPrefix(path + "/") else { throw InvarError("UNSAFE_CLIENT_PROFILE","Client credentials must be outside indexed workspace and daemon Store",exitCode: 8) }
        }
        try FileManager.default.createDirectory(at: selected,withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(selected.path,&info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw InvarError("UNSAFE_CLIENT_PROFILE","Client profile directory must be owned and private",exitCode: 8) }
        self.directory = selected; self.profile = profile; self.workspaceID = workspaceID
    }
    public func connect(endpoint: LocalDaemonEndpoint,label: String?,capabilities: Set<WorkspaceCapability>) async throws -> LocalVerificationClient {
        guard endpoint.workspaceID == workspaceID, !capabilities.contains(.administration) else { throw InvarError("POLICY_DENIED","Ordinary profile cannot change workspace or grant administration",exitCode: 8) }
        let key = Canonical.parts("invar.client-profile/2",[workspaceID,profile])
        let path = directory.appendingPathComponent(key + ".json")
        let lock = open(directory.appendingPathComponent(key + ".lock").path,O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC,0o600)
        guard lock >= 0 else { throw InvarError("PROFILE_UNAVAILABLE","Cannot open client profile lock",exitCode: 6) }
        var client: LocalVerificationClient?
        let result: Result<LocalVerificationClient,any Error>
        do {
            var info = stat()
            guard fstat(lock,&info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw InvarError("UNSAFE_CLIENT_PROFILE","Client profile lock is unsafe",exitCode: 8) }
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while flock(lock,LOCK_EX | LOCK_NB) != 0 {
                guard errno == EWOULDBLOCK || errno == EAGAIN else { throw InvarError("PROFILE_UNAVAILABLE","Cannot lock client profile",exitCode: 6) }
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw InvarError("PROFILE_BUSY","Client profile handshake is busy",exitCode: 6) }
                try await Task.sleep(for: .milliseconds(10))
            }
            let requested = capabilities.sorted { $0.rawValue < $1.rawValue }
            let existing = try read(path)
            if let existing {
                guard existing.workspaceID == workspaceID, existing.profile == profile, existing.engine == endpoint.engineIdentity, existing.capabilities == requested else { throw InvarError("PROFILE_SCOPE_MISMATCH","Choose another profile for a changed engine or capability ceiling",exitCode: 8) }
            }
            let opened = try await LocalVerificationClient.connect(endpoint: endpoint,label: label,capabilities: capabilities,resumeCredential: existing?.credential)
            client = opened
            let credential = try await opened.resumeCredential()
            let record = Record(workspaceID: workspaceID,profile: profile,engine: endpoint.engineIdentity,capabilities: requested,credential: credential)
            let bytes = try Canonical.encode(record)
            if existing != record {
            try bytes.write(to: path,options: .atomic)
            guard chmod(path.path,0o600) == 0 else { throw InvarError("PROFILE_UNAVAILABLE","Cannot protect client credential",exitCode: 8) }
            let handle = try FileHandle(forWritingTo: path)
            do { try handle.synchronize(); try handle.close() }
            catch { do { try handle.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED","Profile sync failed (\(error)); close failed (\(cleanup))") }; throw error }
            let parent = open(directory.path,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard parent >= 0 else { throw InvarError("PROFILE_UNAVAILABLE","Cannot synchronize credential directory") }
            let synchronized = fsync(parent), closed = Darwin.close(parent)
            guard synchronized == 0, closed == 0 else { throw InvarError("CLEANUP_FAILED","Credential directory could not synchronize/close") }
            }
            result = .success(opened)
        } catch { result = .failure(error) }
        let unlocked = flock(lock,LOCK_UN), closed = Darwin.close(lock)
        guard unlocked == 0, closed == 0 else {
            await client?.shutdown()
            throw InvarError("CLEANUP_FAILED","Client profile lock could not release")
        }
        switch result {
        case .success(let value): return value
        case .failure(let error): await client?.shutdown(); throw error
        }
    }
    private func read(_ path: URL) throws -> Record? {
        let descriptor = open(path.path,O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else { throw InvarError("UNSAFE_CLIENT_PROFILE","Cannot read private client credential",exitCode: 8) }
        let handle = FileHandle(fileDescriptor: descriptor,closeOnDealloc: false)
        do {
            var info = stat()
            guard fstat(descriptor,&info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_mode & 0o077 == 0, info.st_size <= 4096 else { throw InvarError("UNSAFE_CLIENT_PROFILE","Unsafe client credential file",exitCode: 8) }
            let bytes = try handle.read(upToCount: 4097) ?? Data()
            guard bytes.count <= 4096 else { throw InvarError("RESOURCE_LIMIT","Client credential record grew beyond its bound",exitCode: 6) }
            let record = try JSONDecoder().decode(Record.self,from: bytes)
            guard (32...256).contains(record.credential.utf8.count) else { throw InvarError("UNSAFE_CLIENT_PROFILE","Invalid client resume credential",exitCode: 8) }
            try handle.close()
            return record
        } catch { do { try handle.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED","Credential read failed (\(error)); close failed (\(cleanup))") }; throw error }
    }
}
