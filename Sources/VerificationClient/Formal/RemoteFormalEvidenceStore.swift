import FormalEvidence
import VerificationCore
import VerificationFormal

public struct RemoteFormalEvidenceStore: FormalEvidenceOpening {
    private let client: any FormalEvidenceQuerying
    private let evidenceID: String
    public init(client: any FormalEvidenceQuerying,evidenceID: String) { self.client = client; self.evidenceID = evidenceID }
    public func open(_ reference: EvidenceBundleReference,budget: EvidenceReadBudget) async throws -> any FormalEvidenceReading {
        let result = try await client.formalQuery(.open(evidenceID: evidenceID,reference: reference,budget: budget))
        guard case .opened(let lease) = result else { throw InvarError("PROTOCOL_MISMATCH","Formal open returned another result variant") }
        guard lease.evidenceID == evidenceID, lease.reference == reference else {
            let original = InvarError("PROTOCOL_MISMATCH","Formal open changed its evidence/bundle binding")
            do {
                let closed = try await client.formalQuery(.close(handle: lease.id))
                guard case .closed = closed else { throw InvarError("PROTOCOL_MISMATCH","Formal cleanup returned another result variant") }
            } catch { throw InvarError("CLEANUP_FAILED","Formal opening failed (\(original)); returned lease close failed (\(error))") }
            throw original
        }
        return RemoteFormalEvidenceReader(client: client,lease: lease)
    }
}
