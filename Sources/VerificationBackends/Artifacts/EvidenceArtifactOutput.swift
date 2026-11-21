import Foundation
import VerificationCore

struct EvidenceArtifactOutput {
    static func json(_ bytes: Data,profile: String,context: BackendContext) throws -> EvidenceArtifactReference {
        guard bytes.count <= context.budget.maximumOutputBytes else { throw InvarError("RESOURCE_LIMIT","Backend artifact exceeds its admitted output budget",exitCode: 6) }
        let hash = Canonical.digest(bytes)
        let reference = EvidenceArtifactReference(id: hash,sha256: hash,byteCount: bytes.count,mediaType: "application/json",profile: profile)
        let directory = try directory(reference,context: context)
        let file = directory.appendingPathComponent("blob")
        if FileManager.default.fileExists(atPath: file.path) {
            let existing = try Data(contentsOf: file,options: .mappedIfSafe)
            guard existing == bytes else { throw InvarError("IMMUTABLE_CONFLICT","Different backend artifact under one digest") }
        } else { try durable(bytes,to: file) }
        return reference
    }
    static func bundle(root: URL,id: String,sha256: String,byteCount: Int,context: BackendContext) throws -> EvidenceArtifactReference {
        let reference = EvidenceArtifactReference(id: id,sha256: sha256,byteCount: byteCount,mediaType: "application/vnd.formal.evidence.sqlite",profile: "formal-evidence/1")
        let destination = try directory(reference,context: context)
        let source = root.appendingPathComponent(id)
        let file = destination.appendingPathComponent("evidence.sqlite")
        // Bundles are closed immutable owners. A same-filesystem hard link avoids
        // re-materializing SQLite while preserving the producer's retained owner.
        if !FileManager.default.fileExists(atPath: file.path) { try FileManager.default.linkItem(at: source.appendingPathComponent("evidence.sqlite"),to: file) }
        let manifest = try Data(contentsOf: source.appendingPathComponent("manifest.json"),options: .mappedIfSafe)
        guard manifest.count <= 4096 else { throw InvarError("RESOURCE_LIMIT","Formal manifest exceeds format bound",exitCode: 6) }
        try durable(manifest,to: destination.appendingPathComponent("manifest.json"))
        return reference
    }
    private static func directory(_ reference: EvidenceArtifactReference,context: BackendContext) throws -> URL {
        try PlanValidation.identifier(reference.id)
        guard reference.id == reference.sha256, reference.byteCount >= 0, reference.byteCount <= context.budget.maximumWorkspaceBytes else { throw InvarError("INVALID_RESULT","Invalid backend artifact reference") }
        let directory = context.outputRoot.appendingPathComponent("artifacts/" + reference.id)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true,attributes: [.posixPermissions:0o700])
        return directory
    }
    private static func durable(_ bytes: Data,to path: URL) throws {
        try bytes.write(to: path,options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath: path.path)
        let handle = try FileHandle(forWritingTo: path)
        do { try handle.synchronize(); try handle.close() }
        catch {
            do { try handle.close() } catch let cleanup { throw InvarError("CLEANUP_FAILED","Artifact sync failed (\(error)); close failed (\(cleanup))") }
            throw error
        }
    }
}
