import Foundation
import Testing
import VerificationCore
import VerificationRuntime
import VerificationStore

@Suite(.timeLimit(.minutes(1))) struct DurableCoordinatorTests {
    actor Authorization: WorkspaceAuthorizationChecking {
        var revision = 1
        func authority(principal: String,operation: WorkspaceOperation,policyRevision: Int,capabilityCeiling: Set<WorkspaceCapability>?) throws -> OperationAuthority {
            guard revision == policyRevision else { throw InvarError("POLICY_DENIED","Policy was revoked",exitCode: 8) }
            let allowed: Set<WorkspaceCapability> = [.read,.verification]
            return OperationAuthority(principal: principal,policyRevision: revision,capabilities: capabilityCeiling.map { allowed.intersection($0) } ?? allowed)
        }
        func revoke() { revision += 1 }
    }
    struct Operations: WorkspaceOperationExecuting {
        func execute(_ demand: RunDemand,authority: OperationAuthority) throws -> String { throw InvarError("UNSUPPORTED_OPERATION","This fixture exposes verification only") }
    }
    func request(store: SQLiteVerificationStore,plan: VerificationPlan,epoch: String,key: String,principal: String = "agent") async throws -> (RequestEnvelope,WorkspaceOperation) {
        let operation = WorkspaceOperation.verify(planID: plan.id,changeRevisionID: nil,replayOfRunID: nil)
        let now = Date().timeIntervalSince1970
        let envelope = RequestEnvelope(id: UUID().uuidString,requestKey: key,principal: principal,workspaceID: plan.body.input.workspaceID,fingerprint: try Canonical.identity(operation),operation: operation.name,daemonEpoch: epoch,policyRevision: 1,expiresAt: now+20,retainUntil: now+30)
        return (try await store.issueEnvelope(envelope,now: now),operation)
    }
    func wait(_ id: String,coordinator: WorkspaceCoordinator,principal: String = "agent") async throws -> RunDemand {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while true {
            let value = try await coordinator.status(id,principal: principal)
            if !["queued","running","cancelling"].contains(value.state) { return value }
            guard ContinuousClock.now < deadline else { throw InvarError("TEST_DEADLINE","Durable operation did not finish") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    @Test func duplicateDeliveryCommitsOneReceiptDemandRunAndView() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let epoch = UUID().uuidString
        try await store.activateEpoch(epoch,engineIdentity: String(repeating: "1",count: 64))
        _ = try await store.observeInput(plan.body.input,epoch: epoch)
        let probe = SharedSchedulingTests.Probe(), scheduler = VerificationScheduler(backend: probe,repository: store,applicability: SchedulerTests.Current(value: "matchesInputs"))
        let coordinator = WorkspaceCoordinator(repository: store,scheduler: scheduler,authorization: Authorization(),operations: Operations(),epoch: epoch,maximumDemands: 8)
        let (envelope,operation) = try await request(store: store,plan: plan,epoch: epoch,key: "once")
        let receipts = try await withThrowingTaskGroup(of: OperationReceipt.self) { group in
            for _ in 0..<20 { group.addTask { try await coordinator.submit(envelope,operation: operation) } }
            var values: [OperationReceipt] = []; for try await receipt in group { values.append(receipt) }; return values
        }
        #expect(receipts.count == 20 && receipts.allSatisfy { $0 == receipts.first })
        let receipt = try #require(receipts.first)
        let terminal = try await wait(receipt.operationID,coordinator: coordinator)
        #expect(terminal.state == "completed"); #expect(await probe.count("a") == 1)
        let run = try await store.loadRun(try #require(terminal.resultID))
        let view = try #require(terminal.view)
        #expect(try await store.latestView(workspaceID: plan.body.input.workspaceID) == nil)
        #expect(try await store.loadView(view.id).runIDs == [run.id])
        #expect(terminal.executionIDs == run.attempts.compactMap(\.executionID))
        #expect(terminal.view == view)
        #expect(try await coordinator.submit(envelope,operation: operation) == receipt)
        try await coordinator.shutdown(); try await store.shutdown()
        let reopened = try SQLiteVerificationStore(root: root)
        #expect(try await reopened.loadReceipt(envelope.id) == receipt)
        #expect(try await reopened.loadDemand(terminal.id) == terminal)
        #expect(try await reopened.latestView(workspaceID: plan.body.input.workspaceID) == nil)
        #expect(try await reopened.loadView(view.id).runIDs == [run.id])
        try await reopened.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test(arguments: 0..<12) func separateDemandsShareWorkerAndCancelOnlyTheirOwnInterest(_ repetition: Int) async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("shared")])
        let epoch = UUID().uuidString
        try await store.activateEpoch(epoch,engineIdentity: String(repeating: "1",count: 64))
        let probe = SharedSchedulingTests.Probe(), scheduler = VerificationScheduler(backend: probe,repository: store,applicability: SchedulerTests.Current(value: "matchesInputs"))
        let coordinator = WorkspaceCoordinator(repository: store,scheduler: scheduler,authorization: Authorization(),operations: Operations(),epoch: epoch,maximumDemands: 8)
        let (a,operation) = try await request(store: store,plan: plan,epoch: epoch,key: "a",principal: "agent-a")
        let (b,_) = try await request(store: store,plan: plan,epoch: epoch,key: "b",principal: "agent-b")
        let first = try await coordinator.submit(a,operation: operation), second = try await coordinator.submit(b,operation: operation)
        #expect(first.operationID != second.operationID)
        try await SharedSchedulingTests().waitForInterests(2,scheduler: scheduler)
        await #expect(throws: InvarError.self) { try await coordinator.cancel(second.operationID,principal: "agent-a") }
        try await coordinator.cancel(first.operationID,principal: "agent-a")
        let cancelled = try await wait(first.operationID,coordinator: coordinator,principal: "agent-a")
        let completed = try await wait(second.operationID,coordinator: coordinator,principal: "agent-b")
        #expect(cancelled.state == "cancelled"); #expect(completed.state == "completed")
        #expect(await probe.count("shared") == 1); #expect(await probe.cancelled == 0)
        try await coordinator.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test func typedFingerprintAndRevokedAuthorityCannotStartAnotherOperation() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let epoch = UUID().uuidString
        try await store.activateEpoch(epoch,engineIdentity: String(repeating: "1",count: 64))
        let authority = Authorization(), probe = SharedSchedulingTests.Probe()
        let scheduler = VerificationScheduler(backend: probe,repository: store)
        let coordinator = WorkspaceCoordinator(repository: store,scheduler: scheduler,authorization: authority,operations: Operations(),epoch: epoch,maximumDemands: 8)
        let (envelope,operation) = try await request(store: store,plan: plan,epoch: epoch,key: "a")
        await #expect(throws: InvarError.self) { try await coordinator.submit(envelope,operation: .verify(planID: plan.id,changeRevisionID: nil,replayOfRunID: "other")) }
        await authority.revoke()
        await #expect(throws: InvarError.self) { try await coordinator.submit(envelope,operation: operation) }
        #expect(try await store.loadReceipt(envelope.id) == nil); #expect(await probe.count("a") == 0)
        try await coordinator.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension DurableCoordinatorTests {
    @Test func recoveryResumesOnlyDurablyAcceptedNeverStartedInternalRequests() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let oldEpoch = UUID().uuidString, engine = String(repeating: "1",count: 64)
        try await store.activateEpoch(oldEpoch,engineIdentity: engine)
        let (queuedEnvelope,operation) = try await request(store: store,plan: plan,epoch: oldEpoch,key: "queued")
        let queuedID = Canonical.parts("invar.operation/2",[queuedEnvelope.id])
        let queued = RunDemand(id: queuedID,envelopeID: queuedEnvelope.id,principal: "agent",origin: "internal",request: operation,planID: plan.id,changeRevisionID: nil,state: "queued",revision: 1,executionIDs: [],resultID: nil,failure: nil)
        _ = try await store.acceptDemand(queuedEnvelope,demand: queued,now: Date().timeIntervalSince1970)
        let (startedEnvelope,_) = try await request(store: store,plan: plan,epoch: oldEpoch,key: "started")
        let startedID = Canonical.parts("invar.operation/2",[startedEnvelope.id])
        let started = RunDemand(id: startedID,envelopeID: startedEnvelope.id,principal: "agent",origin: "internal",request: operation,planID: plan.id,changeRevisionID: nil,state: "queued",revision: 1,executionIDs: [],resultID: nil,failure: nil)
        _ = try await store.acceptDemand(startedEnvelope,demand: started,now: Date().timeIntervalSince1970)
        try await store.transitionDemand(started.transitioning(to: "running"),expectedRevision: 1)
        let now = Date().timeIntervalSince1970
        let providerEnvelope = RequestEnvelope(id: "external-receipt",sessionID: "provider-session",capabilities: [.verification],requestKey: "provider-request",principal: "provider",workspaceID: plan.body.input.workspaceID,fingerprint: queuedEnvelope.fingerprint,operation: operation.name,daemonEpoch: oldEpoch,policyRevision: 1,expiresAt: now+60,retainUntil: now+120)
        _ = try await store.issueEnvelope(providerEnvelope,now: now)
        let base = ProviderActionRegistration(id: "provider-action",envelope: providerEnvelope,operation: operation,input: plan.body.input,sourceFingerprint: String(repeating: "1",count: 64),intent: Data(),authority: Data(),runRequestID: "original-run",run: Data(),expiresAt: now+120)
        try await store.createProviderAction(base)
        try await store.saveProviderActionState(ProviderActionState(id: base.id).revising(state: "accepted",jobID: "external-demand"),expectedRevision: 1)
        let external = RunDemand(id: "external-demand",envelopeID: providerEnvelope.id,principal: "provider",origin: "provider",request: operation,planID: plan.id,changeRevisionID: nil,state: "queued",revision: 1,executionIDs: [],resultID: nil,failure: nil)
        let receipt = OperationReceipt(id: external.envelopeID,operationID: external.id,fingerprint: queuedEnvelope.fingerprint,acceptedAt: now,daemonEpoch: oldEpoch)
        try await store.acceptExternalDemand(receipt,demand: external,actionID: base.id)
        try await store.shutdown()
        let reopened = try SQLiteVerificationStore(root: root), epoch = UUID().uuidString
        try await reopened.activateEpoch(epoch,engineIdentity: engine)
        let probe = SharedSchedulingTests.Probe(), scheduler = VerificationScheduler(backend: probe,repository: reopened,applicability: SchedulerTests.Current(value: "matchesInputs"))
        let coordinator = WorkspaceCoordinator(repository: reopened,scheduler: scheduler,authorization: Authorization(),operations: Operations(),epoch: epoch,maximumDemands: 8)
        try await coordinator.recover()
        let resumed = try await wait(queuedID,coordinator: coordinator)
        #expect(resumed.state == "completed")
        #expect(try await reopened.loadDemand(startedID).state == "interrupted")
        #expect(try await reopened.loadDemand(external.id).state == "notStarted")
        #expect(try await reopened.loadReceipt(external.envelopeID) == receipt)
        #expect(await probe.count("a") == 1)
        try await coordinator.shutdown(); try await reopened.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension DurableCoordinatorTests {
    actor InterestProbe: VerificationBackend {
        let store: SQLiteVerificationStore
        var entered = false, released = false, attachedBeforeLaunch = false
        init(store: SQLiteVerificationStore) { self.store = store }
        func execute(_ context: BackendContext) async throws -> VerificationEvidence {
            let demands = try await store.pendingDemands()
            attachedBeforeLaunch = demands.contains { $0.executionIDs.contains(context.outputRoot.lastPathComponent) }
            entered = true
            while !released { try await Task.sleep(for: .milliseconds(2)) }
            return VerificationEvidence(inputID: context.input.id,jobID: context.job.id,execution: "completed",outcome: "holdsWithinScope",domain: "architecture",translation: "notApplicable",scope: "fixture",adequacy: "completeWithinScope",detail: "fixture",startedAt: Canonical.date(),finishedAt: Canonical.date())
        }
        func release() { released = true }
    }
    @Test func executionInterestsAreDurableBeforeLaunchAndSurviveCancellation() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("shared")])
        let epoch = UUID().uuidString
        try await store.activateEpoch(epoch,engineIdentity: String(repeating: "1",count: 64))
        let probe = InterestProbe(store: store)
        let scheduler = VerificationScheduler(backend: probe,repository: store,applicability: SchedulerTests.Current(value: "matchesInputs"))
        let coordinator = WorkspaceCoordinator(repository: store,scheduler: scheduler,authorization: Authorization(),operations: Operations(),epoch: epoch,maximumDemands: 8)
        let (a,operation) = try await request(store: store,plan: plan,epoch: epoch,key: "early-a")
        let first = try await coordinator.submit(a,operation: operation)
        let (b,_) = try await request(store: store,plan: plan,epoch: epoch,key: "early-b")
        let second = try await coordinator.submit(b,operation: operation)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while true {
            let left = try await store.loadDemand(first.operationID), right = try await store.loadDemand(second.operationID)
            if await probe.entered, !left.executionIDs.isEmpty, !right.executionIDs.isEmpty {
                #expect(left.state == "running" && right.state == "running")
                #expect(left.executionIDs == right.executionIDs)
                let id = try #require(left.executionIDs.first)
                #expect(try await store.loadExecution(id).state == "running")
                break
            }
            guard ContinuousClock.now < deadline else { throw InvarError("TEST_DEADLINE","Durable interests did not precede completion") }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(await probe.attachedBeforeLaunch)
        try await coordinator.cancel(first.operationID,principal: "agent")
        let cancelled = try await store.loadDemand(first.operationID)
        #expect(cancelled.state == "cancelled" && !cancelled.executionIDs.isEmpty)
        await probe.release()
        let terminal = try await wait(second.operationID,coordinator: coordinator)
        #expect(terminal.state == "completed" && terminal.executionIDs == cancelled.executionIDs)
        let (c,_) = try await request(store: store,plan: plan,epoch: epoch,key: "cache")
        let cached = try await coordinator.submit(c,operation: operation)
        let cachedTerminal = try await wait(cached.operationID,coordinator: coordinator)
        #expect(cachedTerminal.executionIDs == terminal.executionIDs)
        try await coordinator.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension DurableCoordinatorTests {
    actor QuotaProbe: VerificationBackend {
        let store: SQLiteVerificationStore
        var exhausted = false
        init(store: SQLiteVerificationStore) { self.store = store }
        func execute(_ context: BackendContext) async throws -> VerificationEvidence {
            for _ in 0..<128 {
                let session = AgentSession(id: UUID().uuidString,principal: "quota-fixture",agentLabel: nil,grants: [],policyRevision: 1,expiresAt: 1)
                do { try await store.saveAgentSession(session) }
                catch let error as InvarError where error.code == "STORE_QUOTA" { exhausted = true; break }
            }
            guard exhausted else { throw InvarError("TEST_PRECONDITION","Fixture did not exhaust ordinary record capacity") }
            throw InvarError("STORE_QUOTA","Backend auxiliary record admission exhausted normal capacity",exitCode: 6)
        }
    }
    @Test(arguments: [1,16]) func normalQuotaRefusalPreservesIncompleteEvidenceAndDrainsReservations(_ reservationLimit: Int) async throws {
        let policy = StorePolicy(maximumRetainedBytes: 8_388_608,maximumDatabaseBytes: 1_048_576,failureReserveBytes: 65_536,maximumRecords: 64,maximumFiles: 1000,maximumReservations: reservationLimit,retentionSeconds: 3600)
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")],policy: policy)
        let epoch = UUID().uuidString
        try await store.activateEpoch(epoch,engineIdentity: String(repeating: "1",count: 64))
        let probe = QuotaProbe(store: store)
        let schedulingPolicy = SchedulingPolicy(maximumWorkers: 1,memoryMiB: 64,maximumProcesses: 8,maximumScratchBytes: plan.body.budget.maximumWorkspaceBytes,maximumReadyJobs: 8,maximumScratchFiles: 100,maximumPriorityBypasses: 2)
        // The job scratch profile must fit the Store's retained-byte ceiling.
        let body = PlanBody(input: plan.body.input,executorIdentity: plan.body.executorIdentity,configurationDigest: plan.body.configurationDigest,jobs: plan.body.jobs,budget: RunBudget(maximumWorkspaceBytes: 1_048_576))
        let smallPlan = VerificationPlan(id: try Canonical.identity(body),body: body)
        try await store.savePlan(smallPlan)
        let scheduler = VerificationScheduler(backend: probe,repository: store,applicability: SchedulerTests.Current(value: "matchesInputs"),policy: schedulingPolicy)
        let coordinator = WorkspaceCoordinator(repository: store,scheduler: scheduler,authorization: Authorization(),operations: Operations(),epoch: epoch,maximumDemands: 8)
        let (envelope,operation) = try await request(store: store,plan: smallPlan,epoch: epoch,key: "full")
        let receipt = try await coordinator.submit(envelope,operation: operation)
        let terminal = try await wait(receipt.operationID,coordinator: coordinator)
        #expect(await probe.exhausted)
        #expect(terminal.state == "completed" && terminal.failure == nil)
        let executionID = try #require(terminal.executionIDs.first)
        let execution = try await store.loadExecution(executionID)
        #expect(execution.state == "completed" && execution.failure == nil)
        let evidenceID = try #require(execution.evidenceID), runID = try #require(terminal.resultID)
        let evidence = try await store.loadEvidence(evidenceID), run = try await store.loadRun(runID)
        #expect(evidence.execution == "resourceLimited" && evidence.outcome == "notEvaluated" && evidence.diagnosticCode == "STORE_QUOTA")
        #expect(!run.accepted && run.attempts == [evidence])
        #expect(try await store.pendingExecutions().isEmpty)
        #expect(try await store.usage().reservationCount == 0)
        #expect(await scheduler.status().activeExecutions == 0)
        try await coordinator.shutdown(); try await store.shutdown()
        let reopened = try SQLiteVerificationStore(root: root,policy: policy)
        #expect(try await reopened.loadDemand(terminal.id) == terminal)
        #expect(try await reopened.loadExecution(executionID) == execution)
        try await reopened.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension DurableCoordinatorTests {
    @Test func recoveryGateRejectsNewRequestsUntilExplicitlyOpened() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let epoch = UUID().uuidString
        try await store.activateEpoch(epoch,engineIdentity: String(repeating: "1",count: 64))
        let probe = SharedSchedulingTests.Probe(), scheduler = VerificationScheduler(backend: probe,repository: store)
        let coordinator = WorkspaceCoordinator(repository: store,scheduler: scheduler,authorization: Authorization(),operations: Operations(),epoch: epoch,maximumDemands: 8,acceptingRequests: false)
        let (envelope,operation) = try await request(store: store,plan: plan,epoch: epoch,key: "gated")
        await #expect(throws: InvarError.self) { try await coordinator.submit(envelope,operation: operation) }
        #expect(try await store.loadReceipt(envelope.id) == nil)
        #expect(await probe.count("a") == 0)
        try await coordinator.openAdmission()
        let receipt = try await coordinator.submit(envelope,operation: operation)
        #expect(try await wait(receipt.operationID,coordinator: coordinator).state == "completed")
        await coordinator.closeAdmission()
        await #expect(throws: InvarError.self) { try await coordinator.openAdmission() }
        try await coordinator.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}
