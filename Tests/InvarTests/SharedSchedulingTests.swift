import Foundation
import Testing
import VerificationCore
import VerificationRuntime
import VerificationStore

@Suite(.timeLimit(.minutes(1))) struct SharedSchedulingTests {
    actor Probe: VerificationBackend {
        var running = 0, peak = 0, calls: [String:Int] = [:], cancelled = 0
        func execute(_ context: BackendContext) async throws -> VerificationEvidence {
            running += 1; peak = max(peak,running); calls[context.job.id,default: 0] += 1
            defer { running -= 1 }
            do { try await Task.sleep(for: .milliseconds(180)) }
            catch { cancelled += 1; throw error }
            return VerificationEvidence(inputID: context.input.id,jobID: context.job.id,execution: "completed",outcome: "holdsWithinScope",domain: "architecture",translation: "notApplicable",scope: "fixture",adequacy: "completeWithinScope",detail: "fixture",startedAt: Canonical.date(),finishedAt: Canonical.date())
        }
        func count(_ id: String) -> Int { calls[id,default: 0] }
    }
    func another(_ original: VerificationPlan,jobs: [VerificationJob],input: VerificationInput? = nil) throws -> VerificationPlan {
        let configuration = VerificationConfiguration(architecture: jobs.compactMap(\.policy))
        let body = PlanBody(input: input ?? original.body.input,executorIdentity: original.body.executorIdentity,configurationDigest: try configuration.identity(),jobs: jobs,budget: original.body.budget)
        return VerificationPlan(id: try Canonical.identity(body),body: body)
    }
    @Test func independentPlansOverlapOnOneScheduler() async throws {
        let (store,first,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let second = try another(first,jobs: [SchedulerTests.job("b")]); try await store.savePlan(second)
        let probe = Probe(), scheduler = VerificationScheduler(backend: probe,repository: store,applicability: SchedulerTests.Current(value: "matchesInputs"))
        async let a = scheduler.run(first.id)
        async let b = scheduler.run(second.id)
        let results = try await [a,b]
        #expect(results.allSatisfy { $0.accepted }); #expect(await probe.peak == 2)
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension SharedSchedulingTests {
    func waitForInterests(_ count: Int,scheduler: VerificationScheduler) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await scheduler.status().interests < count {
            guard ContinuousClock.now < deadline else { throw InvarError("TEST_DEADLINE","Execution interests were not attached") }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
    @Test func sharedJobSurvivesOneDemandCancellationAndReplayExecutesAgain() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("shared")])
        let probe = Probe(), scheduler = VerificationScheduler(backend: probe,repository: store,applicability: SchedulerTests.Current(value: "matchesInputs"))
        let a = Task { try await scheduler.run(plan.id) }
        let b = Task { try await scheduler.run(plan.id) }
        try await waitForInterests(2,scheduler: scheduler)
        a.cancel()
        let cancelled = try await a.value, completed = try await b.value
        #expect(cancelled.attempts.first?.execution == "cancelled")
        #expect(completed.accepted); #expect(await probe.count("shared") == 1)
        #expect(await probe.cancelled == 0)
        let cached = try await scheduler.run(plan.id)
        #expect(cached.attempts == completed.attempts); #expect(await probe.count("shared") == 1)
        let replayed = try await scheduler.run(plan.id,replay: true)
        #expect(replayed.accepted); #expect(await probe.count("shared") == 2)
        #expect(replayed.attempts.first?.id != completed.attempts.first?.id)
        await scheduler.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test func scopedReusePreservesOriginalInputAcrossDifferentPlanInputs() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("shared")])
        let probe = Probe(), scheduler = VerificationScheduler(backend: probe,repository: store,applicability: SchedulerTests.Current(value: "matchesInputs"))
        let first = try await scheduler.run(plan.id)
        let original = DomainTests.inventory(), bytes = Data("unrelated change".utf8)
        let inventory = ScopeInventory(workspaceID: original.workspaceID,snapshotID: "next",contextDigest: original.contextDigest,metadata: original.metadata,entities: original.entities,facts: original.facts,coverage: original.coverage,inputs: [InputEntry(path: "unrelated.txt",digest: Canonical.digest(bytes),byteCount: bytes.count)])
        _ = try await store.saveInput(CapturedWorkspace(inventory: inventory,files: ["unrelated.txt":bytes]))
        let input = try VerificationInput.reference(inventory)
        let secondPlan = try another(plan,jobs: [SchedulerTests.job("shared"),SchedulerTests.job("new")],input: input)
        try await store.savePlan(secondPlan)
        let second = try await scheduler.run(secondPlan.id)
        let retained = try #require(second.attempts.first { $0.jobID == "shared" })
        #expect(second.accepted); #expect(retained == first.attempts.first)
        #expect(retained.inputID != input.id); #expect(await probe.count("shared") == 1)
        #expect(second.associations.contains { $0.evidenceID == retained.id && $0.input == input && $0.reuseDecision == "equalCompleteScopedInputs" })
        #expect(try await store.loadRun(second.id) == second)
        await scheduler.shutdown(); try await store.shutdown()
        let reopened = try SQLiteVerificationStore(root: root)
        #expect(try await reopened.loadRun(second.id) == second)
        let key = try #require(retained.executionKey)
        #expect(try await reopened.reusableEvidence(key: key) == retained)
        try await reopened.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test func aggregateMemoryPolicySerializesDifferentPlans() async throws {
        let (store,first,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let second = try another(first,jobs: [SchedulerTests.job("b")]); try await store.savePlan(second)
        let policy = SchedulingPolicy(maximumWorkers: 2,memoryMiB: 64,maximumProcesses: 16,maximumScratchBytes: 2 * first.body.budget.maximumWorkspaceBytes,maximumReadyJobs: 8,maximumScratchFiles: 1024,maximumPriorityBypasses: 2)
        let probe = Probe(), scheduler = VerificationScheduler(backend: probe,repository: store,applicability: SchedulerTests.Current(value: "matchesInputs"),policy: policy)
        async let a = scheduler.run(first.id)
        async let b = scheduler.run(second.id)
        let results = try await [a,b]
        #expect(results.allSatisfy { $0.accepted }); #expect(await probe.peak == 1)
        #expect(await scheduler.status().reservedMemoryMiB == 0)
        await scheduler.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension SharedSchedulingTests {
    @Test func incompleteGraphNeverSharesOrReusesExecution() async throws {
        let (store,original,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("shared")])
        let inventory = DomainTests.inventory(complete: false)
        _ = try await store.saveInput(CapturedWorkspace(inventory: inventory,files: [:]))
        let input = try VerificationInput.reference(inventory), plan = try another(original,jobs: original.body.jobs,input: input)
        try await store.savePlan(plan)
        let probe = Probe(), scheduler = VerificationScheduler(backend: probe,repository: store)
        async let a = scheduler.run(plan.id)
        async let b = scheduler.run(plan.id)
        let results = try await [a,b]
        #expect(await probe.count("shared") == 2)
        #expect(results.allSatisfy { $0.attempts.first?.executionKey == nil })
        _ = try await scheduler.run(plan.id)
        #expect(await probe.count("shared") == 3)
        await scheduler.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test func lastInterestCancellationDrainsPhysicalExecutionAndReservations() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("shared")])
        let probe = Probe(), scheduler = VerificationScheduler(backend: probe,repository: store)
        let task = Task { try await scheduler.run(plan.id) }
        try await waitForInterests(1,scheduler: scheduler)
        task.cancel()
        let result = try await task.value
        #expect(result.attempts.first?.execution == "cancelled")
        #expect(await probe.running == 0)
        #expect(await scheduler.status().activeExecutions == 0)
        #expect(try await store.usage().reservationCount == 0)
        #expect(try await store.pendingExecutions().isEmpty)
        await scheduler.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension SharedSchedulingTests {
    @Test func concurrentDifferentPlansShareTheOriginalDescriptorWithoutChangingItsInput() async throws {
        let (store,first,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("shared")])
        let second = try another(first,jobs: [SchedulerTests.job("shared"),SchedulerTests.job("additional")])
        try await store.savePlan(second)
        let probe = Probe(), scheduler = VerificationScheduler(backend: probe,repository: store,applicability: SchedulerTests.Current(value: "matchesInputs"))
        async let left = scheduler.run(first.id)
        async let right = scheduler.run(second.id)
        let (a,b) = try await (left,right)
        let original = try #require(a.attempts.first)
        #expect(a.accepted && b.accepted)
        #expect(b.attempts.contains(original))
        #expect(await probe.count("shared") == 1)
        let descriptorID = try #require(original.descriptorID)
        let owner = try await store.loadDescriptor(descriptorID).planID
        #expect(owner == first.id || owner == second.id)
        await scheduler.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}
