import Foundation
import Testing
import FormalValidation
import FormalEvidence
import VerificationClient
import VerificationFormal
import VerificationCore
import VerificationPlanner
import VerificationBackends
import VerificationStore

@Suite(.timeLimit(.minutes(1)), .enabled(if: ProcessInfo.processInfo.environment["INVAR_FORMAL_TOOLCHAIN"] != nil))
struct FormalSDKIntegrationTests {
    @Test func actualPreparedModelAndFormalBundlesSurviveReferenceOnlyContextAndRemoteStore() async throws {
        let toolchain = try #require(ProcessInfo.processInfo.environment["INVAR_FORMAL_TOOLCHAIN"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let store = try SQLiteVerificationStore(root: root)
        let source = Data(("// " + String(repeating: "α",count: 16_384) + "\nfunc increment(_ value: Int64) -> Int64 { return value + 1 }\n").utf8)
        let oracle = Data(#"{"schemaVersion":1,"fuel":64,"cases":[{"name":"positive","entry":"increment","arguments":["2"],"expected":{"status":"returned","value":"3"}}]}"#.utf8)
        let sourceDigest = Canonical.digest(source), oracleDigest = Canonical.digest(oracle)
        let inventory = ScopeInventory(workspaceID: "formal-sdk-" + UUID().uuidString,snapshotID: "snapshot",contextDigest: "context",metadata: ["dependencyStatus":"unknown"],entities: [EntityRecord(id: "file",kind: "file",language: "swift",name: "Source.swift",path: "Source.swift",sourceDigest: sourceDigest,startByte: 0,endByte: source.count)],facts: [],coverage: [],inputs: [InputEntry(path: "Source.swift",digest: sourceDigest,byteCount: source.count),InputEntry(path: "oracle.json",digest: oracleDigest,byteCount: oracle.count)])
        let inputID = try await store.saveInput(CapturedWorkspace(inventory: inventory,files: ["Source.swift":source,"oracle.json":oracle]))
        let executor = String(repeating: "0",count: 64), backend = FormalBackend(), budget = RunBudget(timeoutSeconds: 50,runTimeoutSeconds: 60)
        let key = try PreparedFormalUnit.key(sourceDigest: sourceDigest,language: "swift",executorIdentity: executor)
        let compilationRoot = try await store.preparationOutput(key)
        let compilation = try await backend.prepare(source: source,language: "swift",executorIdentity: executor,output: compilationRoot,budget: budget)
        try await store.savePreparation(compilation)
        let configuration = VerificationConfiguration(formal: [FormalCheck(id: "model",source: "Source.swift",mode: "finite",specification: "oracle.json",toolchain: toolchain,acceptUnvalidatedModel: true)])
        let tools = try backend.toolchainIdentity(at: toolchain)
        let plan = try PlanBuilder().build(inventory: inventory,inputID: inputID,executorIdentity: executor,configuration: configuration,specifications: ["model":oracle],compilations: ["model":compilation],toolchains: ["model":tools],budget: budget)
        try await store.savePlan(plan)
        let output = root.appendingPathComponent("producer")
        try FileManager.default.createDirectory(at: output,withIntermediateDirectories: false)
        let inputRoot = try await store.inputRoot(inputID), job = try #require(plan.body.jobs.first)
        let descriptor = JobDescriptor(planID: plan.id,input: plan.body.input,job: job,executorIdentity: plan.body.executorIdentity,budget: plan.body.budget)
        let descriptorID = try descriptor.identity()
        let context = BackendContext(descriptor: descriptor,descriptorID: descriptorID,inputRoot: inputRoot,outputRoot: output,compilationRoot: compilationRoot,timeoutSeconds: 50,ownerPID: ProcessInfo.processInfo.processIdentifier)
        let wire = try Canonical.encode(context)
        #expect(wire.count < source.count)
        #expect(String(decoding: wire,as: UTF8.self).contains("specificationBytes") == false)
        let evidence = try await backend.execute(context)
        #expect(evidence.execution == "completed" && evidence.outcome == "holdsWithinScope")
        #expect(evidence.domain == "generatedModel" && evidence.translation == "unvalidated")
        #expect(evidence.artifacts.count == 5)
        try await store.adoptArtifacts(evidence,from: output,maximumBytes: budget.maximumWorkspaceBytes)
        let report = try #require(evidence.artifacts.first { $0.profile == "formal-verification/1" })
        let reportRoot = try await store.artifactRoot(report)
        let reportBytes = try Data(contentsOf: reportRoot.appendingPathComponent("blob"))
        let result = try JSONDecoder().decode(FormalVerificationResult.self,from: reportBytes)
        let bundle = try #require(evidence.artifacts.first { $0.id == result.evidence.id })
        let bundleRoot = try await store.artifactRoot(bundle)
        let readBudget = EvidenceReadBudget(maximumDatabaseBytes: budget.maximumWorkspaceBytes,maximumRecordBytes: 262_144,maximumPageBytes: 8_388_608,maximumNodes: 500,maximumEdges: 1500,maximumTraversalNodes: 100_000,maximumCursors: 8)
        let reader = try await LocalFormalEvidenceStore(root: bundleRoot.deletingLastPathComponent()).open(result.evidence,budget: readBudget)
        let catalog = try await reader.catalog()
        #expect(catalog.claims.contains { $0.outcome == "proved" && $0.translation == "UNVALIDATED" })
        #expect(catalog.graphs.contains { $0.kind == .tlaStateSpace && $0.complete && $0.extraction == "available" })
        #expect(catalog.graphs.contains { $0.kind == .leanDeclarations && $0.extraction == "available" })
        try await reader.shutdown()
        let association = EvidenceAssociation.make(evidence: evidence,changeRevisionID: nil,input: plan.body.input,status: "matchesInputs",basis: "Exact original fixed input",unknownBoundaries: ["Upstream project dependencies remain unknown"],reuseDecision: "originalExecution")
        let run = VerificationRun(id: "formal-run",planID: plan.id,attempts: [evidence],associations: [association],accepted: true)
        try await store.saveRun(run)
        #expect(try await store.loadRun(run.id) == run)
        let environment = try await FormalTransportTests.environment(store: store,workspaceID: inventory.workspaceID,engine: executor)
        let client = try await LocalVerificationClient.connect(endpoint: environment.endpoint)
        let remote = try await RemoteFormalEvidenceStore(client: client,evidenceID: evidence.id).open(result.evidence,budget: FormalReadPolicy.development.maximumBudget)
        let remoteCatalog = try await remote.catalog()
        #expect(remoteCatalog == catalog)
        let local = try await LocalFormalEvidenceStore(root: bundleRoot.deletingLastPathComponent()).open(result.evidence,budget: FormalReadPolicy.development.maximumBudget)
        for graph in remoteCatalog.graphs where graph.extraction == "available" {
            #expect(!graph.roots.isEmpty)
            let query = FormalGraphQuery(graphID: graph.id,roots: graph.roots,relations: [],direction: "outgoing",depth: 0)
            let original = try await local.graph(query), received = try await remote.graph(query)
            let stableOriginal = FormalGraphPage(graphID: original.graphID,nodes: original.nodes,edges: original.edges,frontier: original.frontier,selectionComplete: original.selectionComplete)
            let stableReceived = FormalGraphPage(graphID: received.graphID,nodes: received.nodes,edges: received.edges,frontier: received.frontier,selectionComplete: received.selectionComplete)
            let originalDigest = try Canonical.identity(stableOriginal), receivedDigest = try Canonical.identity(stableReceived)
            #expect(originalDigest == receivedDigest)
            #expect((original.nextCursor == nil) == (received.nextCursor == nil))
        }
        if let document = remoteCatalog.documents.first {
            let query = DocumentRangeQuery(documentID: document.id,start: 0,count: min(document.byteCount,4096))
            let original = try await local.document(query), received = try await remote.document(query)
            #expect(original == received)
        }
        try await local.shutdown(); try await remote.shutdown(); await client.shutdown()
        #expect(await environment.readers.activeCount == 0)
        try await environment.shutdown()
        let cached = try await store.loadPreparation(key)
        #expect(cached == compilation)
        try await store.shutdown()
    }
}
