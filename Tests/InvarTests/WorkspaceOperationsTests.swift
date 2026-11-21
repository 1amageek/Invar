import Foundation
import Testing
import VerificationCore
import VerificationDaemon
import VerificationRuntime
import VerificationStore

@Suite(.timeLimit(.minutes(1))) struct WorkspaceOperationsTests {
    actor Source: ArchitectureReading {
        var bytes = Data("let value = 1\n".utf8)
        let workspaceID = "workspace"
        var snapshot = 1, captures = 0
        func update() { bytes = Data("let value = 2\n".utf8); snapshot += 1 }
        func capture() -> CapturedWorkspace {
            captures += 1
            let entry = InputEntry(path: "Code.swift",digest: Canonical.digest(bytes),byteCount: bytes.count)
            let inventory = ScopeInventory(workspaceID: workspaceID,snapshotID: "snapshot-" + String(snapshot),contextDigest: String(repeating: "c",count: 64),metadata: [:],entities: [],facts: [],coverage: DomainTests.inventory().coverage,inputs: [entry])
            return CapturedWorkspace(inventory: inventory,files: [entry.path:bytes])
        }
    }
    func demand(_ operation: WorkspaceOperation,principal: String = "agent") -> RunDemand {
        RunDemand(id: UUID().uuidString,envelopeID: "fixture",principal: principal,origin: "unit-fixture",request: operation,planID: nil,changeRevisionID: nil,state: "running",revision: 2,executionIDs: [],resultID: nil,failure: nil)
    }
    func authority(_ principal: String = "agent") -> OperationAuthority { OperationAuthority(principal: principal,policyRevision: 1,capabilities: [.changes,.planning]) }
    @Test func principalOwnedSealAndHistoricalPreparationUseCapturedContractsAfterLiveRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-operations-" + UUID().uuidString)
        let workspace = root.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace,withIntermediateDirectories: true)
        let config = VerificationConfiguration(architecture: [SchedulerTests.job("cycle").policy!])
        let configBytes = try Canonical.encode(config), configPath = workspace.appendingPathComponent("contracts.json")
        try configBytes.write(to: configPath)
        let store = try SQLiteVerificationStore(root: root.appendingPathComponent("state"))
        let source = Source(), epoch = UUID().uuidString, engine = String(repeating: "0",count: 64), pool = ResourcePool(policy: .development)
        try await store.activateEpoch(epoch,engineIdentity: engine)
        let operations = WorkspaceOperations(source: source,repository: store,resources: pool,workspace: workspace,workspaceID: source.workspaceID,epoch: epoch,engineIdentity: engine,defaultConfigurationPath: "contracts.json",scratchFiles: 1000)
        let claim = ChangeClaim(intent: "Update value",paths: ["Code.swift"],entityIDs: [],patchDigest: nil,expectedFiles: [])
        let first = try await operations.execute(demand(.openChange(claim: claim)),authority: authority())
        let baseline = try await store.loadChange(first)
        #expect(baseline.ownerPrincipal == "agent" && baseline.state == "open")
        let count = await source.captures
        await #expect(throws: InvarError.self) { try await operations.execute(demand(.sealChange(changeID: first),principal: "other"),authority: authority("other")) }
        #expect(await source.captures == count)
        _ = try await operations.execute(demand(.openChange(claim: claim)),authority: authority())
        await source.update()
        let revisionID = try await operations.execute(demand(.sealChange(changeID: first)),authority: authority())
        let revision = try await store.loadChangeRevision(revisionID)
        #expect(revision.before == baseline.baseline && revision.after != baseline.baseline)
        #expect(revision.delta.files.map(\.path) == ["Code.swift"])
        #expect(revision.attribution.kind == "overlapping")
        #expect(try await operations.execute(demand(.sealChange(changeID: first)),authority: authority()) == revisionID)
        try FileManager.default.removeItem(at: configPath)
        let id = try await operations.execute(demand(.preparePlan(configurationPath: "contracts.json",changeRevisionID: revisionID,budget: RunBudget())),authority: authority())
        let plan = try await store.schedulingPlan(id)
        let expectedConfigurationDigest = try config.identity()
        #expect(plan.input == revision.after && plan.configurationDigest == expectedConfigurationDigest)
        #expect(try await store.usage().reservationCount == 0)
        await operations.closeAdmission(); await operations.shutdown(); await pool.shutdown(); try await store.shutdown()
        try FileManager.default.removeItem(at: root)
    }
    @Test func noSymlinkContractCanEscapeTheWorkspaceDuringCapture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-contract-path-" + UUID().uuidString)
        let workspace = root.appendingPathComponent("workspace"), outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: workspace,withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside,withIntermediateDirectories: true)
        let bytes = try Canonical.encode(VerificationConfiguration(architecture: [SchedulerTests.job("cycle").policy!]))
        try bytes.write(to: outside.appendingPathComponent("contracts.json"))
        try FileManager.default.createSymbolicLink(at: workspace.appendingPathComponent("link"),withDestinationURL: outside)
        let store = try SQLiteVerificationStore(root: root.appendingPathComponent("state")), source = Source(), pool = ResourcePool(policy: .development)
        let operations = WorkspaceOperations(source: source,repository: store,resources: pool,workspace: workspace,workspaceID: source.workspaceID,epoch: "epoch",engineIdentity: String(repeating: "0",count: 64),defaultConfigurationPath: nil,scratchFiles: 1000)
        await #expect(throws: InvarError.self) { try await operations.execute(demand(.openChange(claim: nil,configurationPath: "link/contracts.json")),authority: authority()) }
        #expect(await source.captures == 0)
        #expect(try await store.openChanges(workspaceID: source.workspaceID).isEmpty)
        await operations.shutdown(); await pool.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension WorkspaceOperationsTests {
    struct Program: ArchitectureReading {
        let bytes = Data("func compute(_ value: Int64) -> Int64 { return value + 1 }\n".utf8)
        func capture() -> CapturedWorkspace {
            let digest = Canonical.digest(bytes)
            let entry = InputEntry(path: "Code.swift",digest: digest,byteCount: bytes.count)
            let file = EntityRecord(id: "source",kind: "file",language: "swift",name: entry.path,path: entry.path,sourceDigest: digest,startByte: 0,endByte: bytes.count)
            let inventory = ScopeInventory(workspaceID: "workspace",snapshotID: "fixed-program",contextDigest: String(repeating: "c",count: 64),metadata: [:],entities: [file],facts: [],coverage: DomainTests.inventory().coverage,inputs: [entry])
            return CapturedWorkspace(inventory: inventory,files: [entry.path:bytes])
        }
    }
    @Test func formalPreparationCreatesReservedScratchBeforePublishingCompilationAndCleansIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-formal-preparation-" + UUID().uuidString)
        let workspace = root.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace,withIntermediateDirectories: true)
        let source = Program(), engine = String(repeating: "0",count: 64), epoch = UUID().uuidString
        let oracle = Data(#"{"schemaVersion":1,"fuel":64,"cases":[{"name":"positive","entry":"compute","arguments":["2"],"expected":{"status":"returned","value":"3"}}]}"#.utf8)
        try oracle.write(to: workspace.appendingPathComponent("oracle.json"))
        let check = FormalCheck(id: "formal",source: "Code.swift",mode: "finite",specification: "oracle.json",toolchain: root.appendingPathComponent("explicitly-unavailable-tools").path,approved: true,memoryMiB: 4096)
        let configuration = VerificationConfiguration(formal: [check]), configurationBytes = try Canonical.encode(configuration)
        try configurationBytes.write(to: workspace.appendingPathComponent("contracts.json"))
        let store = try SQLiteVerificationStore(root: root.appendingPathComponent("state")), pool = ResourcePool(policy: .development)
        try await store.activateEpoch(epoch,engineIdentity: engine)
        let operations = WorkspaceOperations(source: source,repository: store,resources: pool,workspace: workspace,workspaceID: "workspace",epoch: epoch,engineIdentity: engine,defaultConfigurationPath: nil,scratchFiles: 1000)
        let request = demand(.preparePlan(configurationPath: "contracts.json",changeRevisionID: nil,budget: RunBudget()))
        let id = try await operations.execute(request,authority: authority())
        let plan = try await store.loadPlan(id), job = try #require(plan.body.jobs.first), unit = try #require(job.compilation)
        #expect(unit.sourceDigest == Canonical.digest(source.bytes))
        #expect(try await store.loadPreparation(unit.id) == unit)
        #expect(job.toolchainIdentity == nil && job.memoryMiB == 4096)
        let wal = root.appendingPathComponent("state/verification.sqlite-wal")
        let originalWAL = try Data(contentsOf: wal)
        let originalHead = try await store.sourceHead(workspaceID: "workspace")
        let originalView = try await store.latestView(workspaceID: "workspace")
        for _ in 0..<8 {
            let probe = try await operations.probe(configurationPath: "contracts.json",planID: id,budget: plan.body.budget)
            #expect(!probe.changed)
        }
        #expect(try Data(contentsOf: wal) == originalWAL)
        #expect(try await store.sourceHead(workspaceID: "workspace") == originalHead)
        #expect(try await store.latestView(workspaceID: "workspace") == originalView)
        try (oracle + Data(" ".utf8)).write(to: workspace.appendingPathComponent("oracle.json"))
        let changed = try await operations.probe(configurationPath: "contracts.json",planID: id,budget: plan.body.budget)
        #expect(changed.changed)
        #expect(try Data(contentsOf: wal) == originalWAL)
        try oracle.write(to: workspace.appendingPathComponent("oracle.json"))
        let malformedTools = root.appendingPathComponent("explicitly-unavailable-tools")
        try FileManager.default.createDirectory(at: malformedTools,withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) { try await operations.probe(configurationPath: "contracts.json",planID: id,budget: plan.body.budget) }
        #expect(try Data(contentsOf: wal) == originalWAL)
        let jobBytes = try Canonical.encode(job)
        var changedFields = try #require(JSONSerialization.jsonObject(with: jobBytes) as? [String:Any])
        changedFields["memoryMiB"] = 2048
        let changedBytes = try JSONSerialization.data(withJSONObject: changedFields)
        let changedJob = try JSONDecoder().decode(VerificationJob.self,from: changedBytes)
        let changedBody = PlanBody(input: plan.body.input,executorIdentity: engine,configurationDigest: plan.body.configurationDigest,jobs: [changedJob],budget: plan.body.budget)
        let changedID = try Canonical.identity(changedBody)
        #expect(throws: InvarError.self) { try PlanValidation.validate(VerificationPlan(id: changedID,body: changedBody)) }
        #expect(try await store.usage().reservationCount == 0)
        let scratch = try await store.outputRoot(for: request.id)
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
        #expect(await pool.status(interests: 0).activeExecutions == 0)
        await operations.shutdown(); await pool.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}
