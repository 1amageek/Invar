import Darwin
import Foundation
import VerificationCore

public actor DaemonOwnership: WorkspaceOwnershipHolding {
    public nonisolated let paths: DaemonEndpointPaths
    private var descriptor: Int32
    public init(paths: DaemonEndpointPaths) throws {
        try PlanValidation.identifier(paths.workspaceID)
        guard paths.userID == getuid() else { throw InvarError("INVALID_WORKSPACE","Invalid daemon workspace/user identity",exitCode: 2) }
        if mkdir(paths.runtimeDirectory.path,0o700) != 0, errno != EEXIST { throw InvarError("OWNERSHIP_FAILED","Cannot create private daemon runtime directory",exitCode: 8) }
        var directory = stat()
        guard lstat(paths.runtimeDirectory.path,&directory) == 0, directory.st_uid == getuid(), directory.st_mode & S_IFMT == S_IFDIR, directory.st_mode & 0o077 == 0 else { throw InvarError("OWNERSHIP_FAILED","Unsafe daemon runtime directory",exitCode: 8) }
        let opened = open(paths.ownershipLock.path,O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC,0o600)
        guard opened >= 0 else { throw InvarError("OWNERSHIP_FAILED","Cannot open workspace ownership lock",exitCode: 8) }
        do {
            var info = stat()
            guard fstat(opened,&info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0 else { throw InvarError("OWNERSHIP_FAILED","Unsafe workspace ownership lock",exitCode: 8) }
            guard flock(opened,LOCK_EX | LOCK_NB) == 0 else { throw InvarError("DAEMON_ALREADY_RUNNING","This user/workspace already has an Invar owner",exitCode: 6) }
        } catch { Darwin.close(opened); throw error }
        self.paths = paths; descriptor = opened
    }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
    public func release() throws {
        guard descriptor >= 0 else { return }
        let owned = descriptor; descriptor = -1
        let unlocked = flock(owned,LOCK_UN), closed = Darwin.close(owned)
        guard unlocked == 0, closed == 0 else { throw InvarError("CLEANUP_FAILED","Workspace ownership could not be fully released",exitCode: 7) }
    }
}
