import Foundation
import Testing
import VerificationBackends
import VerificationCore
import VerificationDiscovery
import VerificationRuntime
import VerificationStore

@Suite(.timeLimit(.minutes(1))) struct ReassociationTests {
    struct Current: InputApplicabilityChecking {
        let unknown: [String]
        func applicability(of plan: SchedulingPlan) -> InputComparison {
            InputComparison(target: plan.input,status: "matchesInputs",basis: "Fixture exact comparison",unknownBoundaries: unknown)
        }
    }
    actor CountingStatic: VerificationBackend {
        var calls = 0
        func execute(_ context: BackendContext) async throws -> VerificationEvidence {
            calls += 1
            return try await StaticBackend(evaluator: ArchitectureRuleEvaluator()).execute(context)
        }
    }
    func next(_ original: VerificationPlan,snapshot: String,context: String? = nil) async throws -> CapturedWorkspace {
        let old = DomainTests.inventory()
        let inventory = ScopeInventory(workspaceID: old.workspaceID,snapshotID: snapshot,contextDigest: context ?? old.contextDigest,metadata: old.metadata,entities: old.entities,facts: old.facts,coverage: old.coverage,inputs: old.inputs,originalRecords: old.originalRecords)
        return CapturedWorkspace(inventory: inventory,files: [:])
    }
    func plan(_ capture: CapturedWorkspace,original: VerificationPlan) throws -> VerificationPlan {
        let input = try VerificationInput.reference(capture.inventory)
        let body = PlanBody(input: input,executorIdentity: original.body.executorIdentity,configurationDigest: original.body.configurationDigest,jobs: original.body.jobs,budget: original.body.budget)
        let id = try Canonical.identity(body)
        return VerificationPlan(id: id,body: body)
    }
    func envelope(_ operation: WorkspaceOperation,store: SQLiteVerificationStore,workspace: String,epoch: String) async throws -> RequestEnvelope {
        let now = Date().timeIntervalSince1970, fingerprint = try Canonical.identity(operation)
        let value = RequestEnvelope(id: UUID().uuidString,requestKey: UUID().uuidString,principal: "agent",workspaceID: workspace,fingerprint: fingerprint,operation: operation.name,daemonEpoch: epoch,expiresAt: now+15,retainUntil: now+30)
        return try await store.issueEnvelope(value,now: now)
    }
    @Test(arguments: [false,true]) func sameCapturedScopeCreatesNewViewAndOriginalAxesWithoutAnotherBackendCall(_ priorUnknown: Bool) async throws {
        let (store,original,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("cycle")])
        let backend = CountingStatic(), epoch = UUID().uuidString
        try await store.activateEpoch(epoch,engineIdentity: original.body.executorIdentity)
        _ = try await store.observeInput(original.body.input,epoch: epoch)
        let scheduler = VerificationScheduler(backend: backend,repository: store,applicability: Current(unknown: priorUnknown ? ["Upstream project dependency closure remains unknown"] : []))
        let coordinator = WorkspaceCoordinator(repository: store,scheduler: scheduler,operations: DurableCoordinatorTests.Operations(),epoch: epoch,maximumDemands: 8)
        defer {
            do { try await coordinator.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
        }
        let run = try await scheduler.run(original.id), originalBytes = try Canonical.encode(run)
        #expect(await backend.calls == 1)
        let captured = try await next(original,snapshot: "new-index-generation"), target = try plan(captured,original: original)
        _ = try await store.saveInput(captured); try await store.savePlan(target)
        _ = try await store.observeInput(target.body.input,epoch: epoch)
        let operation = WorkspaceOperation.reconcile(planID: target.id,runID: run.id)
        let request = try await envelope(operation,store: store,workspace: target.body.input.workspaceID,epoch: epoch)
        let receipt = try await coordinator.submit(request,operation: operation)
        let terminal = try await DurableCoordinatorTests().wait(receipt.operationID,coordinator: coordinator)
        #expect(terminal.state == "completed" && terminal.executionIDs.isEmpty)
        let viewID = try #require(terminal.resultID), view = try await store.loadView(viewID)
        #expect(view.input == target.body.input && view.planIDs == [target.id] && view.runIDs == [run.id])
        #expect(view.evidenceIDs == run.attempts.map(\.id))
        #expect(view.associations.allSatisfy { $0.applicability == "matchesInputs" && $0.reuseDecision == "identicalCapturedScope" })
        #expect(view.associations.allSatisfy { $0.unknownBoundaries.contains("Upstream project dependency closure remains unknown") })
        #expect(try await store.latestView(workspaceID: target.body.input.workspaceID) == nil)
        #expect(terminal.view?.id == viewID)
        #expect(await backend.calls == 1)
        let retained = try await store.loadRun(run.id), retainedBytes = try Canonical.encode(retained)
        #expect(retainedBytes == originalBytes)
        for evidence in run.attempts { #expect(try await store.loadEvidence(evidence.id) == evidence) }
    }
    @Test func differentContextAndIncompleteExecutionCannotUseReassociation() async throws {
        let (store,original,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("cycle")])
        let backend = CountingStatic(), epoch = UUID().uuidString
        try await store.activateEpoch(epoch,engineIdentity: original.body.executorIdentity)
        let scheduler = VerificationScheduler(backend: backend,repository: store,applicability: SchedulerTests.Current(value: "matchesInputs"))
        let coordinator = WorkspaceCoordinator(repository: store,scheduler: scheduler,operations: DurableCoordinatorTests.Operations(),epoch: epoch,maximumDemands: 8)
        defer {
            do { try await coordinator.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
        }
        let run = try await scheduler.run(original.id)
        let capture = try await next(original,snapshot: "changed-context",context: "changed-context"), target = try plan(capture,original: original)
        _ = try await store.saveInput(capture); try await store.savePlan(target)
        let operation = WorkspaceOperation.reconcile(planID: target.id,runID: run.id)
        let request = try await envelope(operation,store: store,workspace: target.body.input.workspaceID,epoch: epoch)
        await #expect(throws: InvarError.self) { try await coordinator.submit(request,operation: operation) }
        #expect(try await store.loadReceipt(request.id) == nil)
        #expect(await backend.calls == 1)
        let failures = VerificationScheduler(backend: SchedulerTests.ResourceFailure(),repository: store,applicability: SchedulerTests.Current(value: "matchesInputs"))
        let incomplete = try await failures.run(original.id,replay: true)
        #expect(incomplete.attempts.allSatisfy { $0.execution == "resourceLimited" })
        let same = WorkspaceOperation.reconcile(planID: original.id,runID: incomplete.id)
        let incompleteRequest = try await envelope(same,store: store,workspace: original.body.input.workspaceID,epoch: epoch)
        await #expect(throws: InvarError.self) { try await coordinator.submit(incompleteRequest,operation: same) }
        await failures.shutdown()
    }
}
