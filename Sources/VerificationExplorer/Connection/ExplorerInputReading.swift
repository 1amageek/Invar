import ArchitectureExtensions
import ArchitectureIR

public protocol ExplorerInputReading: Sendable {
    func acquireInputs(snapshotID: String?,maximumBytes: Int,ttl: Int) async throws -> InputLease
    func inputManifest(snapshotID: String,leaseID: String) async throws -> InputManifest
    func scanSnapshot(snapshotID: String,leaseID: String,collection: String,cursor: String?,limit: Int) async throws -> SnapshotPage
    func readInput(leaseID: String,path: String,offset: Int,count: Int) async throws -> InputChunk
    func renewInputs(leaseID: String,ttl: Int) async throws
    func releaseInputs(leaseID: String) async throws
}
