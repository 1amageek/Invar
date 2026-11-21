import ArchitectureCore
import ArchitectureExtensions
import ArchitectureIR
import Foundation
import VerificationCore

/// Captures the complete input manifest and one proven subject without a raw structural-graph scan.
public struct ExplorerProjectReader: Sendable {
    private let client: any ExplorerInputReading
    private let select: @Sendable (String) async throws -> Entity
    public init(client: any ExplorerInputReading,select: @escaping @Sendable (String) async throws -> Entity) { self.client = client; self.select = select }
    public func capture(snapshotID: String?) async throws -> CapturedWorkspace {
        let lease = try await client.acquireInputs(snapshotID: snapshotID,maximumBytes: 64 * 1024 * 1024,ttl: 60)
        let result: Result<CapturedWorkspace,any Error>
        do { result = .success(try await read(lease)) } catch { result = .failure(error) }
        let cleanup = Task { try await client.releaseInputs(leaseID: lease.id) }
        do { try await cleanup.value } catch { throw InvarError("LEASE_RELEASE_FAILED","Project capture (\(result)); lease release failed (\(error))") }
        return try result.get()
    }
    private func read(_ lease: InputLease) async throws -> CapturedWorkspace {
        let manifest = try await client.inputManifest(snapshotID: lease.snapshotID,leaseID: lease.id)
        guard manifest.workspaceID == lease.workspaceID, manifest.snapshotID == lease.snapshotID, manifest.scope == ["."],
            manifest.context == lease.metadata, manifest.contextDigest == lease.contextDigest, manifest.files.count == lease.fileCount else { throw InvarError("INPUT_MISMATCH","Project lease and manifest disagree") }
        let entity = try await select(lease.snapshotID)
        var files: [String:Data] = [:], entries: [InputEntry] = [], total = 0
        var renewal = ContinuousClock.now.advanced(by: .seconds(30))
        for (path,digest) in manifest.files.sorted(by: { $0.key < $1.key }) {
            _ = try Canonical.relative(path)
            var bytes = Data(), eof = false, size: Int?
            while !eof {
                try Task.checkCancellation()
                if ContinuousClock.now >= renewal { try await client.renewInputs(leaseID: lease.id,ttl: 60); renewal = ContinuousClock.now.advanced(by: .seconds(30)) }
                let chunk = try await client.readInput(leaseID: lease.id,path: path,offset: bytes.count,count: 262144)
                guard chunk.digest == digest, chunk.offset == bytes.count, chunk.totalBytes >= 0, chunk.totalBytes <= 5 * 1024 * 1024,
                    size == nil || size == chunk.totalBytes, !chunk.data.isEmpty || chunk.eof else { throw InvarError("INPUT_MISMATCH","Project input chunk changed identity or made no progress") }
                size = chunk.totalBytes; bytes.append(chunk.data); total += chunk.data.count; eof = chunk.eof
                guard bytes.count <= chunk.totalBytes, total <= 64 * 1024 * 1024 else { throw InvarError("RESOURCE_LIMIT","Project capture exceeds input bounds",exitCode: 6) }
            }
            guard bytes.count == size, Canonical.digest(bytes) == digest else { throw InvarError("INPUT_MISMATCH","Project input differs from its manifest") }
            files[path] = bytes; entries.append(InputEntry(path: path,digest: digest,byteCount: bytes.count))
        }
        guard files.count == lease.fileCount, total == lease.totalBytes else { throw InvarError("INCOMPLETE_INPUT","Project capture omitted manifest inputs") }
        let subject = EntityRecord(id: entity.id,kind: entity.kind,language: entity.language,name: entity.name,path: entity.anchor?.path,sourceDigest: entity.anchor?.digest,startByte: entity.anchor?.startByte,endByte: entity.anchor?.endByte)
        let originals = ["inputManifest":[try CanonicalJSON.encode(manifest)],"entities":[try CanonicalJSON.encode(entity)]]
        let coverage = CoverageRecord(producer: "invar.project-inputs",scope: ".",freshness: "current",completeness: "partial",exclusions: ["Structural graph is not scanned; complete original file inputs and one subject are captured."])
        let inventory = ScopeInventory(workspaceID: lease.workspaceID,snapshotID: lease.snapshotID,contextDigest: lease.contextDigest,metadata: lease.metadata,entities: [subject],facts: [],coverage: [coverage],inputs: entries,originalRecords: originals)
        return CapturedWorkspace(inventory: inventory,files: files)
    }
}
