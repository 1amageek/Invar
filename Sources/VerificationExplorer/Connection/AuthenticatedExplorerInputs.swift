import ArchitectureClient
import ArchitectureCore
import ArchitectureExtensions
import ArchitectureIR
import VerificationCore

public struct AuthenticatedExplorerInputs: ExplorerInputReading {
    private let provider: ExtensionProviderClient
    public init(provider: ExtensionProviderClient) throws {
        guard Set(provider.registration.grantedPermissions).isSuperset(of: [.graphRead,.inputsRead]) else { throw InvarError("APPROVAL_REQUIRED","Explorer must grant graph.read and inputs.read",exitCode: 8) }
        self.provider = provider
    }
    public func acquireInputs(snapshotID: String?,maximumBytes: Int,ttl: Int) async throws -> InputLease { try await provider.client.acquireInputs(snapshotID: snapshotID,maximumBytes: maximumBytes,ttl: ttl) }
    public func inputManifest(snapshotID: String,leaseID: String) async throws -> InputManifest {
        let response = try await provider.client.call("inputs.manifest",parameters: .object(["snapshotID":.string(snapshotID),"leaseID":.string(leaseID)]))
        let manifest = try response["manifest"].decode(InputManifest.self)
        let digest = try manifest.digest
        guard manifest.workspaceID == provider.client.paths.workspaceID, manifest.snapshotID == snapshotID, manifest.schemaVersion == "1.0", digest == response["inputManifestDigest"].string else { throw InvarError("INPUT_MISMATCH","Source manifest does not match its owner digest/snapshot") }
        return manifest
    }
    public func scanSnapshot(snapshotID: String,leaseID: String,collection: String,cursor: String?,limit: Int) async throws -> SnapshotPage { try await provider.client.scanSnapshot(snapshotID: snapshotID,leaseID: leaseID,collection: collection,cursor: cursor,limit: limit) }
    public func readInput(leaseID: String,path: String,offset: Int,count: Int) async throws -> InputChunk { try await provider.client.readInput(leaseID: leaseID,path: path,offset: offset,count: count) }
    public func renewInputs(leaseID: String,ttl: Int) async throws {
        let response = try await provider.client.call("inputs.renew",parameters: .object(["leaseID":.string(leaseID),"ttl":.number(Double(ttl))]))
        guard response["id"].string == leaseID, response["expiresAt"].string != nil else { throw InvarError("UPSTREAM_PROTOCOL","Source lease renewal changed identity") }
    }
    public func releaseInputs(leaseID: String) async throws { try await provider.client.releaseInputs(leaseID: leaseID) }
}
