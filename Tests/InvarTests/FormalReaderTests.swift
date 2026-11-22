import FormalEvidence
import Foundation
import Testing
import VerificationClient
import VerificationCore
import VerificationDaemon
import VerificationFormal
import VerificationStore

@Suite(.timeLimit(.minutes(1))) struct FormalReaderTests {
    static func rid(_ name: String) -> String { EvidenceIdentity.id("read-fixture",name) }
    struct Fixture {
        let workspaceID: String
        let root: URL
        let store: SQLiteVerificationStore
        let evidence: VerificationEvidence
        let reference: EvidenceBundleReference
        let document: DocumentReference
    }
    func fixture(shortRetention: Bool = true) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-formal-read-" + UUID().uuidString)
        let base = StorePolicy.development
        let policy = StorePolicy(maximumRetainedBytes: base.maximumRetainedBytes,maximumDatabaseBytes: base.maximumDatabaseBytes,failureReserveBytes: base.failureReserveBytes,maximumRecords: base.maximumRecords,maximumFiles: base.maximumFiles,maximumReservations: base.maximumReservations,retentionSeconds: shortRetention ? 0.001 : 3600)
        let store = try SQLiteVerificationStore(root: root,policy: policy)
        var initialized = false
        defer {
            if !initialized {
                do { try await store.shutdown(); try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
            }
        }
        let original = DomainTests.inventory(), workspaceID = "formal-read-" + UUID().uuidString
        let inventory = ScopeInventory(workspaceID: workspaceID,snapshotID: original.snapshotID,contextDigest: original.contextDigest,metadata: original.metadata,entities: original.entities,facts: original.facts,coverage: original.coverage,inputs: [])
        let inputID = try await store.saveInput(CapturedWorkspace(inventory: inventory,files: [:]))
        let output = root.appendingPathComponent("producer"), budget = FormalReadPolicy.development.maximumBudget
        let writer = try EvidenceBundleWriter(root: output.appendingPathComponent("artifacts"),budget: budget,chunkBytes: 1024)
        let bytes = Data("VARIABLE 日本語\n".utf8)
        let document = DocumentReference(id: Self.rid("source"),sha256: Canonical.digest(bytes),byteCount: bytes.count,language: "tla",role: "source")
        try await writer.document(document,bytes: bytes)
        let descriptor = FormalGraphDescriptor(id: Self.rid("states"),kind: .tlaStateSpace,artifactDigests: [],producer: "read-fixture/1",scope: "Synthetic reader data; no checker result",complete: false,extraction: "available",diagnostics: [])
        try await writer.graph(descriptor)
        let value = StateValue.record(["integer":.integer("123456789012345678901234567890"),"text":.string("日本語")])
        let nodes = [FormalNode(id: Self.rid("state-a"),kind: "state",label: "First",attributes: [:],ranges: [],claimIDs: [],stateValue: value),FormalNode(id: Self.rid("state-b"),kind: "state",label: "Second",attributes: [:],ranges: [],claimIDs: [],stateValue: .boolean(true))]
        let edges = [FormalEdge(id: Self.rid("step"),source: Self.rid("state-a"),target: Self.rid("state-b"),kind: "transition",attributes: [:]),FormalEdge(id: Self.rid("loop"),source: Self.rid("state-b"),target: Self.rid("state-a"),kind: "transition",attributes: [:])]
        try await writer.append(graphID: Self.rid("states"),nodes: nodes,edges: edges)
        try await writer.trace(FormalTrace(id: Self.rid("trace"),graphID: Self.rid("states"),states: [Self.rid("state-a"),Self.rid("state-b")],transitions: [Self.rid("step"),Self.rid("loop")],loopBackIndex: 0,obligation: "Fixture loop ordering",complete: true))
        try await writer.origin(OriginLink(id: Self.rid("origin"),source: TextRange(documentID: document.id,start: 0,end: bytes.count),precision: "exact",producer: "read-fixture/1",synthetic: false))
        let reference = try await writer.seal()
        let artifact = EvidenceArtifactReference(id: reference.id,sha256: reference.sha256,byteCount: reference.byteCount,mediaType: "application/vnd.formal.evidence.sqlite",profile: "formal-evidence/1")
        let evidence = VerificationEvidence(inputID: inputID,jobID: "read-fixture",execution: "completed",outcome: "notEvaluated",domain: "generatedModel",translation: "unvalidated",scope: "Reader fixture",adequacy: "unknown",detail: "Synthetic data is not verification evidence of a program",artifacts: [artifact],startedAt: "fixture",finishedAt: "fixture")
        try await store.adoptArtifacts(evidence,from: output,maximumBytes: 536870912)
        try await store.saveEvidence(evidence)
        initialized = true
        return Fixture(workspaceID: workspaceID,root: root,store: store,evidence: evidence,reference: reference,document: document)
    }
    struct Client: FormalEvidenceQuerying {
        let registry: FormalReaderRegistry
        func formalQuery(_ query: FormalReadQuery) async throws -> FormalReadResult { try await registry.query(query,epoch: "epoch") }
    }
    @Test func originalTypedPagesValuesOriginsAndLoopOrderRoundTripAndCloseReleasesPins() async throws {
        let value = try await fixture(), registry = try FormalReaderRegistry(repository: value.store,workspaceID: value.workspaceID,epoch: "epoch")
        let client = Client(registry: registry)
        let reader = try await RemoteFormalEvidenceStore(client: client,evidenceID: value.evidence.id).open(value.reference,budget: FormalReadPolicy.development.maximumBudget)
        let catalog = try await reader.catalog()
        #expect(catalog.graphs.first?.id == Self.rid("states"))
        let page = try await reader.graph(FormalGraphQuery(graphID: Self.rid("states"),roots: [],relations: [],direction: "outgoing",depth: 0))
        #expect(page.nodes.contains { $0.stateValue == .record(["integer":.integer("123456789012345678901234567890"),"text":.string("日本語")]) })
        let trace = try await reader.trace(FormalTraceQuery(traceID: Self.rid("trace"),start: 0,count: 2))
        #expect(trace.states == [Self.rid("state-a"),Self.rid("state-b")] && trace.transitions == [Self.rid("step"),Self.rid("loop")] && trace.loopBackIndex == 0)
        let origins = try await reader.origins(OriginQuery(documentID: value.document.id,start: 0,count: 4))
        #expect(origins.origins.first?.source?.end == value.document.byteCount)
        let chunk = try await reader.document(DocumentRangeQuery(documentID: value.document.id,start: 0,count: value.document.byteCount))
        #expect(chunk.bytes == Data("VARIABLE 日本語\n".utf8))
        let now = Date().timeIntervalSince1970+3
        _ = try await value.store.prune(now: now,maximumObjects: 100)
        #expect(try await value.store.loadEvidence(value.evidence.id) == value.evidence)
        try await reader.shutdown(); try await reader.shutdown()
        #expect(await registry.activeCount == 0)
        _ = try await value.store.prune(now: now+3,maximumObjects: 100)
        await #expect(throws: InvarError.self) { try await value.store.loadEvidence(value.evidence.id) }
        await #expect(throws: InvarError.self) { try await reader.catalog() }
        try await registry.shutdown(); try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root)
    }
    @Test func readLeaseRejectsWrongEpochAndBundle() async throws {
        let value = try await fixture(), registry = try FormalReaderRegistry(repository: value.store,workspaceID: value.workspaceID,epoch: "epoch")
        let result = try await registry.query(.open(evidenceID: value.evidence.id,reference: value.reference,budget: FormalReadPolicy.development.maximumBudget),epoch: "epoch")
        guard case .opened(let lease) = result else { throw InvarError("TEST_BINDING","No lease") }
        await #expect(throws: InvarError.self) { try await registry.query(.catalog(handle: lease.id),epoch: "other-epoch") }
        await #expect(throws: InvarError.self) { try await registry.query(.close(handle: lease.id),epoch: "other-epoch") }
        let forged = EvidenceBundleReference(id: value.reference.id,sha256: value.reference.sha256,byteCount: value.reference.byteCount+1)
        await #expect(throws: InvarError.self) { try await registry.query(.open(evidenceID: value.evidence.id,reference: forged,budget: FormalReadPolicy.development.maximumBudget),epoch: "epoch") }
        #expect(await registry.activeCount == 1)
        _ = try await registry.query(.close(handle: lease.id),epoch: "epoch")
        try await registry.shutdown(); try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root)
    }
    @Test func capacityAndExpiryAreBoundedAndExpiredReadersReleaseTheirPinClosure() async throws {
        let value = try await fixture()
        let policy = FormalReadPolicy(maximumReaders: 1,leaseSeconds: 1,maximumBudget: FormalReadPolicy.development.maximumBudget)
        let registry = try FormalReaderRegistry(repository: value.store,workspaceID: value.workspaceID,epoch: "epoch",policy: policy)
        let request = FormalReadQuery.open(evidenceID: value.evidence.id,reference: value.reference,budget: policy.maximumBudget)
        _ = try await registry.query(request,epoch: "epoch")
        await #expect(throws: InvarError.self) { try await registry.query(request,epoch: "epoch") }
        try await Task.sleep(for: .milliseconds(1100))
        try await registry.expire()
        #expect(await registry.activeCount == 0)
        _ = try await value.store.prune(now: Date().timeIntervalSince1970+3,maximumObjects: 100)
        await #expect(throws: InvarError.self) { try await value.store.loadEvidence(value.evidence.id) }
        try await registry.shutdown(); try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root)
    }
}
