import ArchitectureCore
import ArchitectureExtensions
import ArchitectureIR
import Foundation
import Testing
import VerificationCore
import VerificationExplorer

@Suite(.timeLimit(.minutes(1))) struct ExplorerCaptureTests {
    actor Source: ExplorerInputReading {
        let bytes = Data("let 日本語 = 1\n".utf8)
        let mode: String
        var acquires = 0, releases = 0, reads = 0, scans = 0
        init(mode: String = "valid") { self.mode = mode }
        func snapshot() -> Snapshot {
            Snapshot(id: "snapshot",workspaceID: "workspace",generation: 1,contextDigest: "context",inputs: ["Code.swift":Canonical.digest(bytes),"@build":"debug"],entities: [],facts: [],evidence: [],coverage: [])
        }
        func acquireInputs(snapshotID: String?,maximumBytes: Int,ttl: Int) throws -> InputLease {
            guard snapshotID == nil, maximumBytes == 64 * 1024 * 1024 else { throw InvarError("TEST_BINDING","Unexpected lease request") }
            acquires += 1
            return InputLease(id: "one-lease",workspaceID: "workspace",snapshotID: "snapshot",contextDigest: "context",metadata: ["@build":"debug"],fileCount: 1,totalBytes: bytes.count,expiresAt: "later")
        }
        func inputManifest(snapshotID: String,leaseID: String) throws -> InputManifest {
            try check(leaseID); return InputManifest(snapshot: snapshot())
        }
        func scanSnapshot(snapshotID: String,leaseID: String,collection: String,cursor: String?,limit: Int) throws -> SnapshotPage {
            try check(leaseID); scans += 1
            guard snapshotID == "snapshot", cursor == nil else { throw InvarError("TEST_BINDING","Scan changed snapshot/cursor") }
            let records: [JSONValue]
            if collection == "inputs" {
                let digest = mode == "wrongManifest" ? String(repeating: "0",count: 64) : Canonical.digest(bytes)
                records = [try JSONValue.encode(CapturedInputFile(path: "Code.swift",digest: digest,byteCount: bytes.count))]
            } else { records = [] }
            return SnapshotPage(workspaceID: "workspace",snapshotID: "snapshot",collection: collection,records: records,total: records.count,nextCursor: nil)
        }
        func readInput(leaseID: String,path: String,offset: Int,count: Int) async throws -> InputChunk {
            try check(leaseID); reads += 1
            if mode == "cancel" { try await Task.sleep(for: .seconds(30)) }
            if mode == "readFailure" { throw InvarError("FIXTURE_READ_FAILED","Original bytes unavailable") }
            return InputChunk(path: path,digest: mode == "wrongManifest" ? String(repeating: "0",count: 64) : Canonical.digest(bytes),totalBytes: bytes.count,offset: offset,data: mode == "wrongBytes" ? Data(repeating: 0,count: bytes.count) : bytes,eof: true)
        }
        func renewInputs(leaseID: String,ttl: Int) throws { try check(leaseID) }
        func releaseInputs(leaseID: String) throws {
            try check(leaseID); releases += 1
            if mode == "releaseFailure" { throw InvarError("FIXTURE_RELEASE_FAILED","Release was not acknowledged") }
        }
        func check(_ lease: String) throws { guard lease == "one-lease", releases == 0 else { throw InvarError("TEST_BINDING","Lease changed or was used after release") } }
    }
    @Test func oneFixedLeasePreservesOwnerManifestAndExactUnicodeBytes() async throws {
        let source = Source(), capture = try await ExplorerSnapshotReader(client: source).capture()
        #expect(await source.acquires == 1)
        #expect(await source.releases == 1)
        #expect(capture.files["Code.swift"] == source.bytes)
        let raw = try #require(capture.inventory.originalRecords["inputManifest"]?.first)
        let manifest = try JSONDecoder().decode(InputManifest.self,from: raw)
        #expect(manifest.dependencyStatus == "unknown")
        #expect(manifest.files["Code.swift"] == Canonical.digest(source.bytes))
        let input = try VerificationInput.reference(capture.inventory)
        let ownerDigest = try manifest.digest
        #expect(input.manifestDigest != ownerDigest)
        #expect(input.dependencyStatus == "unknown")
    }
    @Test(arguments: ["wrongManifest","wrongBytes","readFailure","releaseFailure"])
    func malformedOrUnavailableCaptureReleasesExactlyOnce(_ mode: String) async throws {
        let source = Source(mode: mode)
        await #expect(throws: (any Error).self) { try await ExplorerSnapshotReader(client: source).capture() }
        #expect(await source.acquires == 1)
        #expect(await source.releases == 1)
    }
    @Test func cancellationAwaitsTheSameLeaseRelease() async throws {
        let source = Source(mode: "cancel")
        let task = Task { try await ExplorerSnapshotReader(client: source).capture() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await source.reads == 0 {
            guard ContinuousClock.now < deadline else { throw InvarError("TEST_DEADLINE","Capture did not reach read") }
            try await Task.sleep(for: .milliseconds(2))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await source.releases == 1)
    }
}

extension ExplorerCaptureTests {
    @Test(arguments: ["valid","wrongManifest","wrongBytes","readFailure","releaseFailure"])
    func projectCaptureKeepsAllInputsAndLeaseCleanupWithoutScanningTheStructuralGraph(_ mode: String) async throws {
        let source = Source(mode: mode)
        let reader = ExplorerProjectReader(client: source) { snapshot in
            #expect(snapshot == "snapshot")
            return Entity(id: "system",kind: "softwareSystem",language: "none",name: "System",identityKey: "system",entityRevision: "revision")
        }
        if mode == "valid" {
            let capture = try await reader.capture(snapshotID: nil)
            #expect(capture.files["Code.swift"] == source.bytes)
            #expect(capture.inventory.entities.map(\.id) == ["system"])
            #expect(capture.inventory.facts.isEmpty)
            #expect(capture.inventory.coverage.first?.completeness == "partial")
        } else { await #expect(throws: (any Error).self) { try await reader.capture(snapshotID: nil) } }
        #expect(await source.releases == 1)
        #expect(await source.scans == 0)
    }
}
