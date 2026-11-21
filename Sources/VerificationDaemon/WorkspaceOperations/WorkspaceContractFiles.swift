import Darwin
import Foundation
import VerificationCore

struct WorkspaceContractFiles: Sendable {
    let workspace: URL
    func read(_ relative: String,maximum: Int = 262144) throws -> Data {
        let path = try Canonical.relative(relative), parts = path.split(separator: "/")
        var descriptors: [Int32] = []
        let root = open(workspace.path,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw InvarError("INPUT_UNAVAILABLE","Cannot open canonical workspace") }
        descriptors.append(root)
        let result: Result<Data,any Error>
        do {
            for component in parts.dropLast() {
                let descriptor = openat(descriptors.last!,String(component),O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard descriptor >= 0 else { throw InvarError("ARTIFACT_OUTSIDE_ROOT","Contract parent is absent or contains a symlink",exitCode: 8) }
                descriptors.append(descriptor)
            }
            let descriptor = openat(descriptors.last!,String(parts.last!),O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw InvarError("INPUT_UNAVAILABLE","Cannot open exact workspace contract") }
            var before = stat()
            guard fstat(descriptor,&before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size >= 0, before.st_size <= maximum else {
                let closed = Darwin.close(descriptor)
                guard closed == 0 else { throw InvarError("CLEANUP_FAILED","Rejected contract descriptor could not close") }
                throw InvarError("RESOURCE_LIMIT","Contract is not a bounded regular file",exitCode: 6)
            }
            let handle = FileHandle(fileDescriptor: descriptor,closeOnDealloc: false)
            do {
                let bytes = try handle.read(upToCount: maximum+1) ?? Data()
                var after = stat()
                guard fstat(descriptor,&after) == 0, bytes.count <= maximum, before.st_size == after.st_size, bytes.count == after.st_size,
                    before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
                    before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw InvarError("INPUT_CHANGED","Contract changed during capture") }
                try handle.close(); result = .success(bytes)
            } catch { do { try handle.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED","Contract read failed (\(error)); close failed (\(cleanup))") }; throw error }
        } catch { result = .failure(error) }
        var closeFailed = false
        for descriptor in descriptors.reversed() { if Darwin.close(descriptor) != 0 { closeFailed = true } }
        guard !closeFailed else { throw InvarError("CLEANUP_FAILED","Contract directory descriptor could not close") }
        return try result.get()
    }
    func augment(_ capture: CapturedWorkspace,inputs: [String:Data]) throws -> CapturedWorkspace {
        var files = capture.files, entries = Dictionary(uniqueKeysWithValues: capture.inventory.inputs.map { ($0.path,$0) }), metadata = capture.inventory.metadata
        for (path,bytes) in inputs {
            _ = try Canonical.relative(path)
            guard bytes.count <= 262144 else { throw InvarError("RESOURCE_LIMIT","Contract exceeds its fixed capture profile",exitCode: 6) }
            if let original = files[path], original != bytes { throw InvarError("INPUT_MISMATCH","Contract differs from the retained Explorer source snapshot") }
            let digest = Canonical.digest(bytes)
            files[path] = bytes; entries[path] = InputEntry(path: path,digest: digest,byteCount: bytes.count)
            metadata["@invar.extra:" + path] = digest
        }
        let value = capture.inventory
        return CapturedWorkspace(inventory: ScopeInventory(workspaceID: value.workspaceID,snapshotID: value.snapshotID,contextDigest: value.contextDigest,metadata: metadata,entities: value.entities,facts: value.facts,coverage: value.coverage,inputs: entries.values.sorted { $0.path < $1.path },originalRecords: value.originalRecords,diagnostics: value.diagnostics),files: files)
    }
}
