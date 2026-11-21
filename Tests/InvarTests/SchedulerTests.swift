import Foundation
import Testing
import VerificationCore
import VerificationPlanner
import VerificationRuntime
import VerificationStore

@Suite struct SchedulerTests {
    actor Probe: VerificationBackend {
        var running = Set<String>(), finished = Set<String>(), peak = 0
        var dependentStartedEarly = false
        func execute(_ context: BackendContext) async throws -> VerificationEvidence {
            if context.job.dependencies.contains(where: { !finished.contains($0) }) { dependentStartedEarly = true }
            running.insert(context.job.id); peak = max(peak, running.count)
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { running.remove(context.job.id); throw error }
            running.remove(context.job.id); finished.insert(context.job.id)
            return try DomainTests.evidence(context.job.id)
        }
        func status() -> (Int, Bool, Int) { (peak, dependentStartedEarly, running.count) }
    }
    struct Current: InputApplicabilityChecking {
        let value: String
        func applicability(of plan: SchedulingPlan) async throws -> InputComparison { InputComparison(target: plan.input,status: value,basis: "Fixture exact comparison") }
    }
    static func setup(jobs: [VerificationJob], budget: RunBudget = RunBudget(),policy: StorePolicy = .development) async throws -> (SQLiteVerificationStore, VerificationPlan, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-runtime-" + UUID().uuidString)
        let store = try SQLiteVerificationStore(root: root,policy: policy)
        let inventory = DomainTests.inventory()
        _ = try await store.saveInput(CapturedWorkspace(inventory: inventory, files: [:]))
        let body = PlanBody(input: try VerificationInput.reference(inventory), executorIdentity: String(repeating: "0", count: 64), configurationDigest: try VerificationConfiguration(architecture: jobs.compactMap(\.policy)).identity(), jobs: jobs, budget: budget)
        let plan = VerificationPlan(id: try Canonical.identity(body), body: body)
        try await store.savePlan(plan)
        return (store, plan, root)
    }
    static func job(_ id: String, dependencies: [String] = [], approved: Bool = true, memory: Int = 64) -> VerificationJob {
        VerificationJob(id: id, backend: "static", required: true, approved: approved, dependencies: dependencies,
            policy: ArchitecturePolicy(id: id, kind: "cycle", approved: approved), memoryMiB: memory)
    }
    @Test(.timeLimit(.minutes(1))) func overlapsIndependentJobsAndOrdersDependencies() async throws {
        let (store, plan, root) = try await Self.setup(jobs: [Self.job("a"), Self.job("b"), Self.job("c", dependencies: ["a", "b"])])
        let probe = Probe(), scheduler = VerificationScheduler(backend: probe, repository: store, applicability: Current(value: "matchesInputs"))
        let result = try await scheduler.run(plan.id)
        let status = await probe.status()
        #expect(status.0 == 2)
        #expect(!status.1)
        #expect(status.2 == 0)
        #expect(result.accepted)
        #expect(try await store.loadRun(result.id) == result)
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test(.timeLimit(.minutes(1))) func admitsMemoryAndBlocksUnapprovedOrInfeasibleJobs() async throws {
        let (store, plan, root) = try await Self.setup(jobs: [Self.job("a"), Self.job("b"), Self.job("blocked", approved: false), Self.job("large", memory: 128)], budget: RunBudget(memoryMiB: 64))
        let probe = Probe()
        let result = try await VerificationScheduler(backend: probe, repository: store, applicability: Current(value: "matchesInputs")).run(plan.id)
        #expect(await probe.status().0 == 1)
        #expect(result.attempts.filter { $0.execution == "blocked" }.count == 2)
        #expect(!result.accepted)
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test(.timeLimit(.minutes(1))) func cancellationDrainsAndPersistsIncompleteWork() async throws {
        let (store, plan, root) = try await Self.setup(jobs: [Self.job("a"), Self.job("b")])
        let probe = Probe(), scheduler = VerificationScheduler(backend: probe, repository: store)
        let task = Task { try await scheduler.run(plan.id) }
        try await Task.sleep(for: .milliseconds(20)); task.cancel()
        let result = try await task.value
        #expect(!result.accepted)
        #expect(result.attempts.allSatisfy { $0.execution == "cancelled" })
        #expect(await probe.status().2 == 0)
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test(.timeLimit(.minutes(1))) func staleCompletionCannotPassCI() async throws {
        let (store, plan, root) = try await Self.setup(jobs: [Self.job("a")])
        let result = try await VerificationScheduler(backend: Probe(), repository: store, applicability: Current(value: "stale")).run(plan.id)
        #expect(result.attempts[0].outcome == "holdsWithinScope")
        #expect(result.associations[0].applicability == "stale")
        #expect(!result.accepted)
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test func rejectsTraversalAndCyclesBeforeExecution() async throws {
        let (store, plan, root) = try await Self.setup(jobs: [Self.job("a")])
        for jobs in [[Self.job("../escape")], [Self.job("a", dependencies: ["b"]), Self.job("b", dependencies: ["a"])]] {
            let body = PlanBody(input: plan.body.input, executorIdentity: plan.body.executorIdentity, configurationDigest: try VerificationConfiguration(architecture: jobs.compactMap(\.policy)).identity(), jobs: jobs, budget: RunBudget())
            #expect(throws: (any Error).self) { try PlanValidation.validate(VerificationPlan(id: Canonical.identity(body), body: body)) }
        }
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
    struct ResourceFailure: VerificationBackend {
        func execute(_ context: BackendContext) async throws -> VerificationEvidence { throw InvarError("RESOURCE_LIMIT", "Measured resource exhaustion", exitCode: 6) }
    }
    actor Slow: VerificationBackend {
        private(set) var running = false
        func execute(_ context: BackendContext) async throws -> VerificationEvidence {
            running = true; defer { running = false }
            try await Task.sleep(for: .seconds(30))
            return try DomainTests.evidence(context.job.id)
        }
    }
    @Test(.timeLimit(.minutes(1))) func deadlineDrainsAndRemainsDistinctFromResourceExhaustion() async throws {
        let (store, plan, root) = try await Self.setup(jobs: [Self.job("a")], budget: RunBudget(timeoutSeconds: 1))
        let slow = Slow()
        let timed = try await VerificationScheduler(backend: slow, repository: store, applicability: Current(value: "matchesInputs")).run(plan.id)
        #expect(timed.attempts[0].execution == "timeout")
        #expect(timed.attempts[0].diagnosticCode == "TIMEOUT")
        #expect(!timed.accepted)
        #expect(await !slow.running)
        let limited = try await VerificationScheduler(backend: ResourceFailure(), repository: store, applicability: Current(value: "matchesInputs")).run(plan.id)
        #expect(limited.attempts[0].execution == "resourceLimited")
        #expect(limited.attempts[0].diagnosticCode == "RESOURCE_LIMIT")
        #expect(!limited.accepted)
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }

}
