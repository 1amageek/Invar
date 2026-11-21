import FormalEvidence
import Foundation
import Testing
import VerificationClient
import VerificationCore
import VerificationFormal

@Suite(.timeLimit(.minutes(1))) struct RemoteFormalOpenCleanupTests {
    actor Query: FormalEvidenceQuerying {
        private let lease: FormalReadLease
        private let failClose: Bool
        private(set) var closed: [String] = []
        init(lease: FormalReadLease,failClose: Bool) { self.lease = lease; self.failClose = failClose }
        func formalQuery(_ query: FormalReadQuery) throws -> FormalReadResult {
            switch query {
            case .open: return .opened(lease)
            case .close(let id):
                closed.append(id)
                if failClose { throw InvarError("TEST_CLOSE_FAILED","Injected close failure") }
                return .closed
            default: throw InvarError("TEST_UNEXPECTED_QUERY","No reader may escape this altered opening")
            }
        }
    }
    @Test(arguments: [false,true]) func alteredOpenedBindingClosesItsReturnedLeaseAndReportsCleanupFailure(_ failClose: Bool) async throws {
        let reference = EvidenceBundleReference(id: EvidenceIdentity.id("cleanup","bundle"),sha256: String(repeating: "0",count: 64),byteCount: 1)
        let lease = FormalReadLease(id: "returned-private-handle",epoch: "epoch",evidenceID: "different-evidence",reference: reference,expiresAt: Date().timeIntervalSince1970+30)
        let query = Query(lease: lease,failClose: failClose)
        let store = RemoteFormalEvidenceStore(client: query,evidenceID: "expected-evidence")
        do {
            _ = try await store.open(reference,budget: FormalReadPolicy.development.maximumBudget)
            Issue.record("Altered evidence binding returned a reader")
        } catch let failure as InvarError {
            #expect(failure.code == (failClose ? "CLEANUP_FAILED" : "PROTOCOL_MISMATCH"))
        }
        #expect(await query.closed == [lease.id])
    }
}
