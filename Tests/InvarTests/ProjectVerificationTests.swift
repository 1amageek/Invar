import Foundation
import Testing
import VerificationCore
import VerificationPlanner
import VerificationBackends
import FormalCore
import VerificationDaemon
import VerificationRuntime
import VerificationStore

@Suite(.timeLimit(.minutes(1))) struct ProjectVerificationTests {
    let builder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("plugins/invar/scripts/project_report.py")
    func fixture(mutate: Bool = false,delay: Bool = false,stage: ProjectCheck.Stage? = nil) throws -> (URL,BackendContext) {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("invar-project-" + UUID().uuidString)
        let input = root.appendingPathComponent("input"), output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: input,withIntermediateDirectories: true)
        let script = """
        import json,hashlib,time
        from pathlib import Path
        \(delay ? "time.sleep(5)" : "")
        root=Path.cwd(); run=root/'Verification/Project/runs/test'; run.mkdir(parents=True)
        def ref(p):
            return {'path':str(p.relative_to(root)), 'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
        log=run/'checker.log'; log.write_text('asserted arithmetic fixture: 1 + 1 == 2')
        receipt={'schemaVersion':2,'activity':'specificationCheck','command':['fixture-checker'],'executed':True,'exitCode':0,'inputs':[ref(root/'Code.swift'),ref(root/'SPEC.md')], 'outputs':[ref(log)],'claims':[{'id':'spec','requirements':['A01'],'domain':'specification.lean.quantified','outcome':'passed','scope':'Orchestration fixture only','method':'proof','obligations':[{**ref(root/'SPEC.md'),'selector':'A01'}]}]}
        r=run/'receipt.json';r.write_text(json.dumps(receipt))
        manifest={'schemaVersion':2,'title':'Fixture verification','productionInputs':[ref(root/'Code.swift')],'reviews':[],'inventory':{'source':ref(root/'SPEC.md'),'sections':[{'heading':'## Acceptance','kind':'table'}]},'requirements':[{'id':'A01','specification':{'claims':['spec']},'implementation':{'claims':[],'reason':'No source check'},'correspondence':{'claims':[],'reason':'No validated translation'}}],'receipts':[ref(r)]}
        m=run/'manifest.json';m.write_text(json.dumps(manifest))
        import importlib.util
        spec=importlib.util.spec_from_file_location('builder',\(String(reflecting: builder.path)));mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
        report=root/'Verification/Project/Report.json';report.write_text(json.dumps(mod.build(root,manifest)))
        \(mutate ? "(root/'Code.swift').write_text('changed')" : "")
        print(json.dumps({'manifest':str(m.relative_to(root)), 'report':str(report.relative_to(root))}))
        raise SystemExit(6)
        """
        let files = ["check.py":Data(script.utf8),"SPEC.md":Data("## Acceptance\n| A01 | Addition | Returns two |\n".utf8),"Code.swift":Data("func add() -> Int { 1 + 1 }\n".utf8)]
        for (path,bytes) in files { try bytes.write(to: input.appendingPathComponent(path)) }
        let entries = files.map { InputEntry(path: $0.key,digest: Canonical.digest($0.value),byteCount: $0.value.count) }.sorted { $0.path < $1.path }
        let budget = RunBudget(memoryMiB: 1024,timeoutSeconds: delay ? 0.2 : 15,runTimeoutSeconds: 30,maximumCPUSeconds: 15)
        let validBudget = RunBudget(memoryMiB: 1024,timeoutSeconds: 15,runTimeoutSeconds: 30,maximumCPUSeconds: 15)
        let python = "/usr/bin/python3"
        let check = ProjectCheck(id: "project",subjectID: "system",command: [python,"check.py"],toolDigests: [python:Canonical.digest(try Data(contentsOf: URL(fileURLWithPath: python))),builder.path:Canonical.digest(try Data(contentsOf: builder))],reportBuilder: builder.path,report: "Verification/Project/Report.json",contracts: ["SPEC.md","check.py"],budget: validBudget,approved: true,stage: stage)
        let configuration = VerificationConfiguration(project: check)
        let decoded = try ConfigurationReader.decode(try Canonical.encode(configuration))
        #expect(decoded.project?.stage == stage)
        let inventory = ScopeInventory(workspaceID: "workspace",snapshotID: "snapshot",contextDigest: String(repeating: "c",count: 64),metadata: [:],entities: [],facts: [],coverage: [],inputs: entries)
        let reference = try VerificationInput.reference(inventory)
        let plan = try PlanBuilder().build(inventory: inventory,inputID: reference.id,executorIdentity: String(repeating: "0",count: 64),configuration: VerificationConfiguration(project: check),specifications: [:],toolchains: [:],budget: validBudget)
        try PlanValidation.validate(plan); try PlanValidation.bind(plan,to: inventory)
        let expandedBudget = RunBudget(timeoutSeconds: 300)
        let forged = JobDescriptor(planID: plan.id,input: plan.body.input,job: plan.body.jobs[0],executorIdentity: plan.body.executorIdentity,budget: expandedBudget)
        #expect(throws: InvarError.self) { try PlanValidation.descriptor(forged) }
        let descriptor = ExecutionBinding.descriptor(plan: plan,job: plan.body.jobs[0])
        let context = BackendContext(descriptor: descriptor,descriptorID: try descriptor.identity(),inputRoot: input,outputRoot: output,timeoutSeconds: budget.timeoutSeconds,ownerPID: ProcessInfo.processInfo.processIdentifier,nativeExecutionAllowed: true)
        return (root,context)
    }
    @Test func realWorkflowRetainsIncompleteReportAndDoesNotUseLiveSources() async throws {
        let (root,context) = try fixture(); defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let evidence = try await ProjectBackend().execute(context)
        #expect(evidence.execution == "completed" && evidence.outcome == "unknown" && evidence.domain == "projectContract")
        #expect(evidence.artifacts.count == 2 && Set(evidence.artifacts.map(\.profile)) == ["project-report/1","project-evidence/1"])
        try PlanValidation.evidence(evidence,job: context.job)
        #expect(try String(contentsOf: context.inputRoot.appendingPathComponent("Code.swift"),encoding: .utf8).contains("1 + 1"))
    }
    @Test func greenfieldVerificationRejectsSealedSourceBeforeExecuting() async throws {
        let (root,context) = try fixture(stage: .greenfieldSpecification)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        do { _ = try await ProjectBackend().execute(context); Issue.record("Production source was accepted in the greenfield phase") }
        catch let error as InvarError { #expect(error.code == "GREENFIELD_SOURCE_PRESENT") }
        #expect(!FileManager.default.fileExists(atPath: context.outputRoot.path))
    }
    @Test func changedReceiptsCannotBecomeAResult() async throws {
        let (root,context) = try fixture(mutate: true); defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        do { _ = try await ProjectBackend().execute(context); Issue.record("Changed receipts were accepted") }
        catch let error as InvarError { #expect(error.code == "INVALID_RESULT" || error.code == "INPUT_MISMATCH") }
    }
    @Test func cancellationDeadlineCannotProduceAReport() async throws {
        let (root,context) = try fixture(delay: true); defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        do { _ = try await ProjectBackend().execute(context); Issue.record("Deadline produced a report") }
        catch let error as FormalDiagnostic { #expect(error.code == .timeout) }
    }
    @Test func explicitCancellationStopsTheOwnedWorkflow() async throws {
        let (root,context) = try fixture(delay: true); defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let task = Task { try await ProjectBackend().execute(context) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled execution produced evidence") }
        catch is CancellationError {}
    }
    actor ProjectInputs: ProjectArchitectureReading {
        let captured: CapturedWorkspace
        var projectReads = 0
        init(_ captured: CapturedWorkspace) { self.captured = captured }
        func capture() throws -> CapturedWorkspace { throw InvarError("UNEXPECTED_GRAPH_SCAN","Project applicability must keep its file-input profile") }
        func captureProject(snapshotID: String?,entityID: String) -> CapturedWorkspace {
            #expect(entityID == "system"); projectReads += 1; return captured
        }
    }
    @Test func projectPlanningAndPostRunApplicabilityKeepTheSameCaptureProfile() async throws {
        let (root,context) = try fixture(); defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let configuration = VerificationConfiguration(project: context.job.project)
        let bytes = try Canonical.encode(configuration)
        try bytes.write(to: context.inputRoot.appendingPathComponent("invar.json"))
        var files = ["invar.json":bytes]
        for entry in context.job.inputs { files[entry.path] = try Data(contentsOf: context.inputRoot.appendingPathComponent(entry.path)) }
        let entries = files.map { InputEntry(path: $0.key,digest: Canonical.digest($0.value),byteCount: $0.value.count) }.sorted { $0.path < $1.path }
        let inventory = ScopeInventory(workspaceID: "workspace",snapshotID: "snapshot",contextDigest: String(repeating: "c",count: 64),metadata: [:],entities: [],facts: [],coverage: [],inputs: entries)
        let source = ProjectInputs(CapturedWorkspace(inventory: inventory,files: files))
        let store = try SQLiteVerificationStore(root: root.appendingPathComponent("state")), pool = ResourcePool(policy: .development)
        let engine = String(repeating: "0",count: 64)
        try await store.activateEpoch("epoch",engineIdentity: engine)
        let operations = WorkspaceOperations(source: source,repository: store,resources: pool,workspace: context.inputRoot,workspaceID: "workspace",epoch: "epoch",engineIdentity: engine,defaultConfigurationPath: "invar.json",scratchFiles: 1000)
        do {
            let operation = WorkspaceOperation.preparePlan(configurationPath: "invar.json",changeRevisionID: nil,budget: context.descriptor.budget)
            let demand = WorkspaceOperationsTests().demand(operation)
            let id = try await operations.execute(demand,authority: OperationAuthority(principal: "agent",policyRevision: 1,capabilities: [.planning]))
            let plan = try await store.schedulingPlan(id)
            let comparison = try await operations.applicability(of: plan)
            #expect(comparison.status == "matchesInputs")
            #expect(await source.projectReads == 2)
        } catch {
            await operations.shutdown();await pool.shutdown();try await store.shutdown();throw error
        }
        await operations.shutdown();await pool.shutdown();try await store.shutdown()
    }
    @Test func wholeProjectVerdictCannotOmitAPhaseOrPromoteIncompleteCoverage() throws {
        for rows in [[], [["id":"A01","specification":["outcome":"passed"]]]] as [[Any]] {
            let bytes = try JSONSerialization.data(withJSONObject: ["metadata":["verificationReport":["inventory":["A01"],"requirements":rows,"outcome":"passed"]]])
            #expect(throws: (any Error).self) { try ProjectReportAssessment.outcome(bytes) }
        }
    }
    @Test func passedLabelsWithoutClaimsAndReviewedGatesAreRejected() throws {
        let row: [String:Any] = ["id":"A01","specification":["outcome":"passed","claims":[]],"implementation":["outcome":"passed","claims":[]],"correspondence":["outcome":"passed","claims":[]]]
        let bytes = try JSONSerialization.data(withJSONObject: ["metadata":["verificationReport":["inventory":["A01"],"requirements":[row],"outcome":"passed"]]])
        #expect(throws: (any Error).self) { try ProjectReportAssessment.outcome(bytes) }
    }
}
