import ArchitectureCore
import Foundation
import Testing
import VerificationCore
import VerificationDaemon
import VerificationStore
@testable import VerificationRuntime

@Suite(.timeLimit(.minutes(1))) struct WatchRegistryTests {
    actor Events: SourceEventReading {
        private var changed = true
        private var ready = true
        private(set) var polls = 0
        func invalidate(ready: Bool) { changed = true; self.ready = ready }
        func poll() -> SourceEvent {
            polls += 1
            let invalidated = changed; changed = false
            return SourceEvent(epoch: "source-epoch",snapshotID: "source",sequence: 1,ready: ready,invalidated: invalidated,continuityLost: invalidated,reason: invalidated ? (ready ? "Fixture source resync" : "Fixture source analysis pending") : nil)
        }
    }
    actor Inputs: WorkspaceOperationExecuting, WatchInputProbing {
        let repository: SQLiteVerificationStore
        let plan: VerificationPlan
        let epoch: String
        private(set) var preparations = 0
        private(set) var probes = 0
        private(set) var running = false
        private var blocked = false
        init(repository: SQLiteVerificationStore,plan: VerificationPlan,epoch: String) { self.repository = repository; self.plan = plan; self.epoch = epoch }
        func block() { blocked = true }
        func execute(_ demand: RunDemand) async throws -> String {
            guard case .preparePlan = demand.request else { throw InvarError("TEST_UNEXPECTED_OPERATION","Watch source fixture only prepares its retained exact plan") }
            running = true; preparations += 1
            defer { running = false }
            while blocked { try await Task.sleep(for: .milliseconds(5)) }
            _ = try await repository.observeInput(plan.body.input,epoch: epoch)
            return plan.id
        }
        func probe(configurationPath: String,planID: String,budget: RunBudget) -> WatchInputProbe { probes += 1; return WatchInputProbe(changed: false,reason: nil) }
    }
    let policy = WatchPolicy(pollSeconds: 0.01,probeSeconds: 0.05,retrySeconds: 0.1,settleSeconds: 0,maximumSettleSeconds: 0.05,maximumConcurrentCycles: 2)
    func wait(_ condition: @escaping @Sendable () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !(try await condition()) {
            guard ContinuousClock.now < deadline else { throw InvarError("TEST_DEADLINE","Watch registry condition timed out") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    @Test func quietMonitoringAndDaemonDetachPreserveRegistrationAndReassociateWithoutAnotherWorker() async throws {
        let value = try await WatchRecordTests().fixture(), events = Events(), backend = ReassociationTests.CountingStatic()
        let inputs = Inputs(repository: value.store,plan: value.plan,epoch: value.epoch)
        let scheduler = VerificationScheduler(backend: backend,repository: value.store,applicability: SchedulerTests.Current(value: "matchesInputs"))
        let coordinator = WorkspaceCoordinator(repository: value.store,scheduler: scheduler,operations: inputs,epoch: value.epoch,maximumDemands: 8)
        let registry = try WatchRegistry(repository: value.store,coordinator: coordinator,events: events,probe: inputs,workspaceID: value.record.workspaceID,epoch: value.epoch,policy: policy)
        defer {
            do { try await registry.shutdown(); try await coordinator.shutdown(); try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root) } catch { Issue.record(error) }
        }
        let record = try await WatchRecordTests().register(value)
        try await registry.start()
        try await wait {
            let watch = try await value.store.loadWatch(record.id)
            return watch.lastView != nil && watch.cycle.phase == "idle"
        }
        let first = try await value.store.loadWatch(record.id)
        try await wait { await inputs.probes >= 3 }
        #expect(try await value.store.loadWatch(record.id) == first)
        #expect(await backend.calls == 1)
        try await registry.shutdown()
        #expect(try await value.store.loadWatch(record.id).state == "active")
        let replacement = try WatchRegistry(repository: value.store,coordinator: coordinator,events: Events(),probe: inputs,workspaceID: record.workspaceID,epoch: value.epoch,policy: policy)
        defer { do { try await replacement.shutdown() } catch { Issue.record(error) } }
        try await replacement.start()
        try await wait {
            let watch = try await value.store.loadWatch(record.id)
            return watch.cycle.generation == 2 && watch.cycle.phase == "idle"
        }
        let second = try await value.store.loadWatch(record.id)
        #expect(second.lastRunID == first.lastRunID && second.lastView != first.lastView)
        #expect(await backend.calls == 1)
        _ = try await replacement.stop(record.id,principal: record.principal)
        #expect(try await value.store.loadWatch(record.id).state == "stopped")
    }
    @Test func sourcePumpInvalidatesDuringBlockedPreparationAndExplicitStopAwaitsItsCleanup() async throws {
        let value = try await WatchRecordTests().fixture(), events = Events()
        let inputs = Inputs(repository: value.store,plan: value.plan,epoch: value.epoch)
        await inputs.block()
        let scheduler = VerificationScheduler(backend: SchedulerTests.ResourceFailure(),repository: value.store)
        let coordinator = WorkspaceCoordinator(repository: value.store,scheduler: scheduler,operations: inputs,epoch: value.epoch,maximumDemands: 8)
        let registry = try WatchRegistry(repository: value.store,coordinator: coordinator,events: events,probe: inputs,workspaceID: value.record.workspaceID,epoch: value.epoch,policy: policy)
        defer {
            do { try await registry.shutdown(); try await coordinator.shutdown(); try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root) } catch { Issue.record(error) }
        }
        let record = try await WatchRecordTests().register(value)
        _ = try await value.store.observeInput(value.plan.body.input,epoch: value.epoch)
        try await registry.start()
        try await wait { await inputs.running }
        let before = try #require(try await value.store.sourceHead(workspaceID: record.workspaceID))
        await events.invalidate(ready: false)
        try await wait {
            let source = try await value.store.sourceHead(workspaceID: record.workspaceID)
            return (source?.revision ?? 0) > before.revision
        }
        #expect(try await value.store.sourceHead(workspaceID: record.workspaceID)?.confirmed == false)
        _ = try await registry.stop(record.id,principal: record.principal)
        #expect(!(await inputs.running))
        #expect(try await value.store.loadWatch(record.id).state == "stopped")
        #expect(await coordinator.activeCount == 0)
        #expect(await events.polls > 1)
    }
}
