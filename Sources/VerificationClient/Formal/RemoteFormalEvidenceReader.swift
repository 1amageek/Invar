import FormalEvidence
import VerificationCore
import VerificationFormal

public actor RemoteFormalEvidenceReader: FormalEvidenceReading {
    private let client: any FormalEvidenceQuerying
    public nonisolated let lease: FormalReadLease
    private var stopped = false
    init(client: any FormalEvidenceQuerying,lease: FormalReadLease) { self.client = client; self.lease = lease }
    public func catalog() async throws -> EvidenceCatalog {
        try ensureOpen(); let result = try await client.formalQuery(.catalog(handle: lease.id))
        guard case .catalog(let value) = result else { throw mismatch() }; return value
    }
    public func graph(_ query: FormalGraphQuery) async throws -> FormalGraphPage {
        try ensureOpen(); let result = try await client.formalQuery(.graph(handle: lease.id,query: query))
        guard case .graph(let value) = result, value.graphID == query.graphID else { throw mismatch() }; return value
    }
    public func trace(_ query: FormalTraceQuery) async throws -> FormalTracePage {
        try ensureOpen(); let result = try await client.formalQuery(.trace(handle: lease.id,query: query))
        guard case .trace(let value) = result else { throw mismatch() }; return value
    }
    public func origins(_ query: OriginQuery) async throws -> OriginPage {
        try ensureOpen(); let result = try await client.formalQuery(.origins(handle: lease.id,query: query))
        guard case .origins(let value) = result else { throw mismatch() }; return value
    }
    public func document(_ query: DocumentRangeQuery) async throws -> DocumentChunk {
        try ensureOpen(); let result = try await client.formalQuery(.document(handle: lease.id,query: query))
        guard case .document(let value) = result else { throw mismatch() }; return value
    }
    public func shutdown() async throws {
        if stopped { return }
        let result = try await client.formalQuery(.close(handle: lease.id))
        guard case .closed = result else { throw mismatch() }
        stopped = true
    }
    private func ensureOpen() throws { guard !stopped else { throw InvarError("READ_LEASE_EXPIRED","Remote formal reader is closed",exitCode: 6) } }
    private func mismatch() -> InvarError { InvarError("PROTOCOL_MISMATCH","Daemon returned a different formal read result") }
}
