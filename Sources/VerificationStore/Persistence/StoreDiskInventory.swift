import Darwin
import Foundation
import VerificationCore

struct StoreDiskInventory {
    struct Entry: Sendable { let path: String; let bytes: Int; let modifiedAt: Double; let directory: Bool }
    struct Snapshot: Sendable { let bytes: Int; let files: Int; let databaseBytes: Int; let entries: [Entry] }
    static func scan(root: URL,maximumFiles: Int) throws -> Snapshot {
        // realpath owns one allocation in this scope. Copy before exactly one free;
        // no pointer escapes. Foundation enumerators use /private/var while their
        // input URL may retain /var, so prefix accounting must use the OS path.
        guard let resolved = root.path.withCString({ realpath($0,nil) }) else { throw InvarError("STORE_IO_FAILED","Cannot resolve private Store root") }
        let physical = String(cString: resolved); free(resolved)
        let directory = URL(fileURLWithPath: physical,isDirectory: true)
        var enumerationFailure: (any Error)?
        guard let enumerator = FileManager.default.enumerator(at: directory,includingPropertiesForKeys: nil,errorHandler: { _,error in enumerationFailure = error; return false }) else { throw InvarError("STORE_IO_FAILED","Cannot enumerate private Store") }
        var entries: [Entry] = [], total = 0, database = 0
        while let path = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            guard entries.count < maximumFiles else { throw InvarError("RESOURCE_LIMIT","Store file count exceeds policy",exitCode: 6) }
            var info = stat()
            let measured = lstat(path.path,&info)
            if measured != 0, errno == ENOENT || errno == ESTALE { throw InvarError("STORE_SCAN_CHANGED","Published paths moved during capacity measurement") }
            guard measured == 0, info.st_size >= 0, info.st_size <= Int.max - total else { throw InvarError("STORE_IO_FAILED","Cannot measure retained file") }
            guard path.path.hasPrefix(physical + "/") else { throw InvarError("STORE_INTEGRITY","Enumeration escaped its physical root") }
            let relative = String(path.path.dropFirst(physical.count+1)), directory = info.st_mode & S_IFMT == S_IFDIR
            let size = directory ? 0 : Int(info.st_size)
            total += size
            if ["verification.sqlite","verification.sqlite-wal","verification.sqlite-shm"].contains(relative) { database += size }
            entries.append(Entry(path: relative,bytes: size,modifiedAt: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec)/1e9,directory: directory))
        }
        if let enumerationFailure {
            let failure = enumerationFailure as NSError
            if failure.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(failure.code) { throw InvarError("STORE_SCAN_CHANGED","Published directory moved during capacity enumeration") }
            throw InvarError("STORE_IO_FAILED","Capacity enumeration did not visit every owned entry: \(enumerationFailure)")
        }
        return Snapshot(bytes: total,files: entries.count,databaseBytes: database,entries: entries)
    }
}
