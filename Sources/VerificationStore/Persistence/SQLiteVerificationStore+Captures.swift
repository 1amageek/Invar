import Foundation
import VerificationCore

extension SQLiteVerificationStore {
    public func capture(_ input: VerificationInput) throws -> CapturedWorkspace {
        try ensureAccepting()
        let catalog = try inventory(input), directory = try inputLocation(input)
        var files: [String:Data] = [:], total = 0
        for entry in catalog.inputs {
            try Task.checkCancellation()
            guard entry.byteCount <= 5 * 1024 * 1024, entry.byteCount <= 256 * 1024 * 1024 - total else { throw InvarError("RESOURCE_LIMIT","Sealed capture exceeds materialization profile",exitCode: 6) }
            let bytes = try bounded(directory.appendingPathComponent(entry.path),maximum: entry.byteCount)
            guard bytes.count == entry.byteCount, Canonical.digest(bytes) == entry.digest else { throw InvarError("STORE_INTEGRITY","Sealed capture bytes differ") }
            total += bytes.count; files[entry.path] = bytes
        }
        return CapturedWorkspace(inventory: catalog,files: files)
    }
    public func adoptPreparation(_ value: PreparedFormalUnit,from output: URL) throws {
        try ensureAccepting()
        let destination = try preparationOutput(value.id)
        let key = try PreparedFormalUnit.key(sourceDigest: value.sourceDigest,language: value.language,executorIdentity: value.executorIdentity)
        guard key == value.id else { throw InvarError("INPUT_MISMATCH","Prepared unit key differs") }
        let manifest = try bounded(output.appendingPathComponent("compilation.json"),maximum: 32768)
        let source = try bounded(output.appendingPathComponent("source.txt"),maximum: 1_000_000)
        guard Canonical.digest(manifest) == value.manifest.sha256, manifest.count == value.manifest.byteCount, Canonical.digest(source) == value.sourceDigest else { throw InvarError("STORE_INTEGRITY","Prepared scratch source/manifest differs") }
        if let existing = try loadPreparation(value.id) {
            guard existing == value else { throw InvarError("IMMUTABLE_CONFLICT","Published compilation differs") }
            return
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw InvarError("RECOVERY_BLOCKED","Unpublished preparation requires recovery before replacement",exitCode: 6) }
        try FileManager.default.moveItem(at: output,to: destination)
        try synchronizeDirectory(destination.deletingLastPathComponent())
        try savePreparation(value)
        try transferOwnership(from: output,relativeRoot: "prepared/" + value.id,objectKind: "preparation",objectID: value.id)
        resourceRevision += 1
    }
}
