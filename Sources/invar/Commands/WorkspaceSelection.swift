import ArchitectureCore
import Darwin
import Foundation
import VerificationCore
import VerificationDaemon

struct WorkspaceSelection {
    static func resolve(_ explicit: String?) throws -> URL {
        if let explicit {
            guard !explicit.isEmpty else {
                throw InvarError("INVALID_ARGUMENT", "--workspace requires a directory", exitCode: 2)
            }
            let paths = try WorkspacePaths(explicit)
            return paths.root
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var directory = try DaemonPathValidation.canonical(cwd)
        while true {
            if try hasGitDirectory(in: directory) { return directory }
            guard directory.path != "/" else {
                throw InvarError("WORKSPACE_REQUIRED", "No Git workspace contains the current directory. Pass --workspace to select a directory.", exitCode: 2)
            }
            directory.deleteLastPathComponent()
        }
    }

    private static func hasGitDirectory(in directory: URL) throws -> Bool {
        let marker = directory.appendingPathComponent(".git").resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: marker.path) else { return false }
        let values = try marker.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
        if values.isDirectory == true {
            return FileManager.default.fileExists(atPath: marker.appendingPathComponent("HEAD").path)
        }
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 4096 else { return false }
        let bytes = try marker.withUnsafeFileSystemRepresentation { path -> Data in
            guard let path else { throw InvarError("INVALID_WORKSPACE", "Invalid Git marker path", exitCode: 2) }
            return try readGitMarker(at: path)
        }
        guard bytes.count <= 4096, let contents = String(data: bytes, encoding: .utf8), contents.hasPrefix("gitdir: ") else {
            return false
        }
        let path = String(contents.dropFirst("gitdir: ".count)).trimmingCharacters(in: .newlines)
        guard !path.isEmpty, !path.contains("\0") else { return false }
        let gitDirectory = URL(fileURLWithPath: path, relativeTo: directory)
        return FileManager.default.fileExists(atPath: gitDirectory.appendingPathComponent("HEAD").path)
    }

    private static func readGitMarker(at path: UnsafePointer<CChar>) throws -> Data {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw InvarError("INVALID_WORKSPACE", "Cannot read Git marker", exitCode: 2) }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= 4096 else { return Data() }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        return try file.read(upToCount: 4097) ?? Data()
    }
}
