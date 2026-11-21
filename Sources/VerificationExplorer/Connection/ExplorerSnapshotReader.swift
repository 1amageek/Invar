import ArchitectureExtensions
import ArchitectureCore
import ArchitectureIR
import Foundation
import VerificationCore

public struct ExplorerSnapshotReader: ArchitectureReading {
    private let client: any ExplorerInputReading
    private let snapshotID: String?
    public init(client: any ExplorerInputReading,snapshotID: String? = nil) { self.client = client; self.snapshotID = snapshotID }
    public func capture() async throws -> CapturedWorkspace {
        let lease = try await client.acquireInputs(snapshotID: snapshotID,maximumBytes: 64 * 1024 * 1024,ttl: 60)
        let result: Result<CapturedWorkspace,any Error>
        do { result = .success(try await read(lease)) } catch { result = .failure(error) }
        // This scope owns the lease. Await uncancelled cleanup exactly once;
        // cleanup failure is observable even when the capture was cancelled.
        let cleanup = Task { try await client.releaseInputs(leaseID: lease.id) }
        do { try await cleanup.value }
        catch { throw InvarError("LEASE_RELEASE_FAILED","Capture result (\(result)); release failed (\(error))") }
        return try result.get()
    }
    private func read(_ lease: InputLease) async throws -> CapturedWorkspace {
            let manifest = try await client.inputManifest(snapshotID: lease.snapshotID,leaseID: lease.id)
            guard manifest.workspaceID == lease.workspaceID, manifest.contextDigest == lease.contextDigest, manifest.context == lease.metadata,
                manifest.files.count == lease.fileCount, manifest.scope == ["."], manifest.dependencyStatus == "unknown" else { throw InvarError("INPUT_MISMATCH","Lease/manifest scope and context differ") }
            var renewal = ContinuousClock.now.advanced(by: .seconds(30))
            func renewIfNeeded() async throws {
                if ContinuousClock.now >= renewal {
                    try await client.renewInputs(leaseID: lease.id,ttl: 60)
                    renewal = ContinuousClock.now.advanced(by: .seconds(30))
                }
            }
            var original: [String: [Data]] = [:], all: [String: [JSONValue]] = [:], total = 0
            for collection in ["entities", "facts", "evidence", "coverage", "diagnostics", "inputs"] {
                var cursor: String?, seen = Set<String>(), values: [JSONValue] = []
                repeat {
                    try Task.checkCancellation(); try await renewIfNeeded()
                    let page = try await client.scanSnapshot(snapshotID: lease.snapshotID, leaseID: lease.id, collection: collection, cursor: cursor, limit: 500)
                    guard page.snapshotID == lease.snapshotID && page.workspaceID == lease.workspaceID else { throw InvarError("INPUT_MISMATCH", "Raw scan mixed snapshots") }
                    for value in page.records {
                        let bytes = try CanonicalJSON.encode(value); total += bytes.count
                        guard total <= 64 * 1024 * 1024, values.count < 250000 else { throw InvarError("RESOURCE_LIMIT", "Raw inventory exceeds its byte/record budget", exitCode: 6) }
                        original[collection, default: []].append(bytes); values.append(value)
                    }
                    if let next = page.nextCursor { guard seen.insert(next).inserted else { throw InvarError("INVALID_CURSOR", "Raw scan repeated its cursor") } }
                    cursor = page.nextCursor
                    if cursor == nil, values.count != page.total { throw InvarError("INCOMPLETE_INVENTORY", "Raw scan lost records") }
                } while cursor != nil
                all[collection] = values
            }
            let entities = try all["entities", default: []].map { value -> EntityRecord in
                let entity = try value.decode(Entity.self)
                return EntityRecord(id: entity.id, kind: entity.kind, language: entity.language, name: entity.name,
                    path: entity.anchor?.path, sourceDigest: entity.anchor?.digest, startByte: entity.anchor?.startByte, endByte: entity.anchor?.endByte)
            }
            let facts = try all["facts", default: []].map { value -> FactRecord in
                let fact = try value.decode(Fact.self)
                return FactRecord(id: fact.id, kind: fact.kind, source: fact.source, target: fact.target, producer: fact.producer, scope: fact.scope, evidenceIDs: fact.evidenceIDs)
            }
            let ids = Set(entities.map(\.id)), edgeIDs = Set(facts.map(\.id)), evidenceIDs = Set(all["evidence", default: []].compactMap { $0["id"].string })
            guard ids.count == entities.count, edgeIDs.count == facts.count,
                facts.allSatisfy({ ids.contains($0.source) && ids.contains($0.target) && Set($0.evidenceIDs).isSubset(of: evidenceIDs) }) else {
                throw InvarError("INVALID_GRAPH", "Raw inventory has duplicate identities or dangling references")
            }
            let coverage = try all["coverage", default: []].map { value -> CoverageRecord in
                let item = try value.decode(Coverage.self)
                return CoverageRecord(producer: item.producer, scope: item.scope, freshness: item.freshness, completeness: item.completeness, exclusions: item.exclusions)
            }
            var files: [String: Data] = [:], entries: [InputEntry] = [], bytesRead = 0
            for record in all["inputs", default: []] {
                let item = try record.decode(CapturedInputFile.self)
                _ = try Canonical.relative(item.path)
                guard let size = item.byteCount, size >= 0, size <= 5 * 1024 * 1024, files[item.path] == nil else { throw InvarError("INVALID_INPUT", "Missing size or duplicate original path") }
                var bytes = Data(), eof = false
                while !eof {
                    try Task.checkCancellation(); try await renewIfNeeded()
                    let chunk = try await client.readInput(leaseID: lease.id, path: item.path, offset: bytes.count, count: 262144)
                    guard chunk.digest == item.digest && chunk.totalBytes == size && chunk.offset == bytes.count,
                        !chunk.data.isEmpty || chunk.eof else { throw InvarError("INPUT_MISMATCH", "Original input chunk changed identity or made no progress") }
                    bytes.append(chunk.data); bytesRead += chunk.data.count; eof = chunk.eof
                    guard bytes.count <= size && bytesRead <= 64 * 1024 * 1024 else { throw InvarError("RESOURCE_LIMIT", "Original inputs exceed capture budget", exitCode: 6) }
                }
                guard bytes.count == size && Canonical.digest(bytes) == item.digest && manifest.files[item.path] == item.digest else { throw InvarError("INPUT_MISMATCH", "Original source digest does not match manifest") }
                files[item.path] = bytes; entries.append(InputEntry(path: item.path, digest: item.digest, byteCount: size))
            }
            guard files.count == lease.fileCount && bytesRead == lease.totalBytes else { throw InvarError("INCOMPLETE_INPUT", "Captured inputs do not match lease totals") }
            guard Set(files.keys) == Set(manifest.files.keys) else { throw InvarError("INCOMPLETE_INPUT","Manifest and leased file set differ") }
            original["inputManifest"] = [try CanonicalJSON.encode(manifest)]
            let inventory = ScopeInventory(workspaceID: lease.workspaceID, snapshotID: lease.snapshotID, contextDigest: lease.contextDigest, metadata: lease.metadata,
                entities: entities, facts: facts, coverage: coverage, inputs: entries.sorted { $0.path < $1.path }, originalRecords: original,
                diagnostics: all["diagnostics", default: []].map { ($0["code"].string ?? "DIAGNOSTIC") + ": " + ($0["message"].string ?? "Unknown diagnostic") })
            return CapturedWorkspace(inventory: inventory, files: files)
    }
}
