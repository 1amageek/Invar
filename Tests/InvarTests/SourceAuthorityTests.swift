import Foundation
import Testing
import VerificationCore
import VerificationStore

@Suite(.timeLimit(.minutes(1))) struct SourceAuthorityTests {
    @Test func differentContractClosuresOfTheSameExplorerSnapshotDoNotInvalidateTheWorkspaceSourceFence() async throws {
        let value = try await PublicationTests().fixture()
        defer { do { try await PublicationTests().cleanup(value) } catch { Issue.record(error) } }
        let base = try await value.store.inventory(value.plan.body.input)
        func augmented(_ path: String) -> CapturedWorkspace {
            let bytes = Data(path.utf8), digest = Canonical.digest(bytes)
            var metadata = base.metadata; metadata["@invar.extra:" + path] = digest
            let inventory = ScopeInventory(workspaceID: base.workspaceID,snapshotID: base.snapshotID,contextDigest: base.contextDigest,metadata: metadata,entities: base.entities,facts: base.facts,coverage: base.coverage,inputs: [InputEntry(path: path,digest: digest,byteCount: bytes.count)],originalRecords: base.originalRecords)
            return CapturedWorkspace(inventory: inventory,files: [path:bytes])
        }
        let first = augmented("first.json"), second = augmented("second.json")
        _ = try await value.store.saveInput(first); _ = try await value.store.saveInput(second)
        let a = try VerificationInput.reference(first.inventory), b = try VerificationInput.reference(second.inventory)
        #expect(a.id != b.id && a.semanticDigest != b.semanticDigest)
        let before = try await value.store.observeInput(a,epoch: value.epoch)
        let after = try await value.store.observeInput(b,epoch: value.epoch)
        #expect(before == after)
        let invalid = try #require(try await value.store.invalidateSource(workspaceID: a.workspaceID,epoch: value.epoch,reason: "Independent source event"))
        let confirmed = try await value.store.observeInput(b,epoch: value.epoch)
        #expect(confirmed.confirmed && confirmed.revision == invalid.revision+1)
    }
}
