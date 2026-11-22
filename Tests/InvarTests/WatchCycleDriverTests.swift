import Foundation
import Testing
import VerificationCore
import VerificationStore
@testable import VerificationRuntime

@Suite(.timeLimit(.minutes(1))) struct WatchCycleDriverTests {
    actor Inputs: WorkspaceOperationExecuting, WatchInputProbing {
        private var planID: String
        private(set) var preparations = 0
        init(planID: String) { self.planID = planID }
        func select(_ id: String) { planID = id }
        func execute(_ demand: RunDemand) async throws -> String {
            guard case .preparePlan = demand.request else { throw InvarError("TEST_UNEXPECTED_OPERATION","Cycle fixture only prepares an existing exact plan") }
            preparations += 1
            return planID
        }
        func probe(configurationPath: String,planID: String,budget: RunBudget) -> WatchInputProbe { WatchInputProbe(changed: planID != self.planID,reason: nil) }
    }
    @Test func quietProbeDoesNotWriteAndSameScopeUsesOriginalEvidenceWithTheExactOperationView() async throws {
        let value = try await WatchRecordTests().fixture()
        let inputs = Inputs(planID: value.plan.id), backend = ReassociationTests.CountingStatic()
        let scheduler = VerificationScheduler(backend: backend,repository: value.store,applicability: SchedulerTests.Current(value: "matchesInputs"))
        let coordinator = WorkspaceCoordinator(repository: value.store,scheduler: scheduler,operations: inputs,epoch: value.epoch,maximumDemands: 8)
        let lifecycle = WatchLifecycle(repository: value.store,coordinator: coordinator)
        let driver = WatchCycleDriver(repository: value.store,coordinator: coordinator,probe: inputs,lifecycle: lifecycle)
        defer {
            do { try await lifecycle.shutdown(); try await coordinator.shutdown(); try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root) } catch { Issue.record(error) }
        }
        let registered = try await WatchRecordTests().register(value)
        _ = try await value.store.observeInput(value.plan.body.input,epoch: value.epoch)
        try await driver.run(registered.id,force: true)
        let first = try await value.store.loadWatch(registered.id)
        #expect(first.state == "active" && first.cycle == WatchCycle(generation: 1))
        #expect(first.lastPlanID == value.plan.id && first.lastRunID != nil && first.lastView != nil)
        #expect(await backend.calls == 1)
        #expect(await inputs.preparations == 1)
        for _ in 0..<5 { try await driver.run(registered.id,force: false) }
        #expect(try await value.store.loadWatch(registered.id) == first)
        #expect(await inputs.preparations == 1)
        let nextCapture = try await ReassociationTests().next(value.plan,snapshot: "cycle-next-snapshot")
        let nextPlan = try ReassociationTests().plan(nextCapture,original: value.plan)
        _ = try await value.store.saveInput(nextCapture); try await value.store.savePlan(nextPlan)
        _ = try await value.store.observeInput(nextPlan.body.input,epoch: value.epoch)
        await inputs.select(nextPlan.id)
        try await driver.run(registered.id,force: true)
        let next = try await value.store.loadWatch(registered.id)
        #expect(next.cycle == WatchCycle(generation: 2) && next.lastPlanID == nextPlan.id && next.lastRunID == first.lastRunID)
        #expect(await backend.calls == 1)
        #expect(await inputs.preparations == 2)
        let id = WatchRequestIdentity.demandID(watchID: registered.id,generation: 2,operation: "verification.reconcile")
        let result = try await value.store.loadDemand(id)
        #expect(result.state == "completed" && result.executionIDs.isEmpty && next.lastView == result.view)
        let reference = try #require(next.lastView)
        let view = try await value.store.loadView(reference.id)
        let originalRunID = try #require(first.lastRunID)
        #expect(view.input == nextPlan.body.input && view.runIDs == [originalRunID])
    }
    @Test func resumesAnAcceptedPreparationWithoutMintingAReplacementDemand() async throws {
        let value = try await WatchRecordTests().fixture()
        let inputs = Inputs(planID: value.plan.id), backend = ReassociationTests.CountingStatic()
        let scheduler = VerificationScheduler(backend: backend,repository: value.store,applicability: SchedulerTests.Current(value: "matchesInputs"))
        let coordinator = WorkspaceCoordinator(repository: value.store,scheduler: scheduler,operations: inputs,epoch: value.epoch,maximumDemands: 8)
        let lifecycle = WatchLifecycle(repository: value.store,coordinator: coordinator)
        let driver = WatchCycleDriver(repository: value.store,coordinator: coordinator,probe: inputs,lifecycle: lifecycle)
        defer {
            do { try await lifecycle.shutdown(); try await coordinator.shutdown(); try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root) } catch { Issue.record(error) }
        }
        let registered = try await WatchRecordTests().register(value)
        _ = try await value.store.observeInput(value.plan.body.input,epoch: value.epoch)
        let preparing = registered.revising(state: "active",cycle: WatchCycle(generation: 1,phase: "preparing"))
        try await value.store.saveWatch(preparing,expectedRevision: registered.revision)
        let receipt = try await coordinator.submitWatch(watchID: registered.id,operation: .preparePlan(configurationPath: registered.configurationPath,changeRevisionID: nil,budget: registered.budget))
        try await driver.run(registered.id,force: true)
        #expect(await inputs.preparations == 1)
        #expect(await backend.calls == 1)
        let retained = try await value.store.loadReceipt(WatchRequestIdentity.envelopeID(watchID: registered.id,generation: 1,operation: "plan.prepare"))
        #expect(retained == receipt)
        let watch = try await value.store.loadWatch(registered.id)
        #expect(watch.cycle == WatchCycle(generation: 1) && watch.lastPlanID == value.plan.id)
    }
    @Test func cancellingDriverDrainsItsAcceptedChildBeforeReturning() async throws {
        let value = try await WatchRecordTests().fixture(), preparation = WatchLifecycleTests.Preparation()
        let inputs = Inputs(planID: value.plan.id)
        let scheduler = VerificationScheduler(backend: SchedulerTests.ResourceFailure(),repository: value.store)
        let coordinator = WorkspaceCoordinator(repository: value.store,scheduler: scheduler,operations: preparation,epoch: value.epoch,maximumDemands: 8)
        let lifecycle = WatchLifecycle(repository: value.store,coordinator: coordinator)
        let driver = WatchCycleDriver(repository: value.store,coordinator: coordinator,probe: inputs,lifecycle: lifecycle)
        defer {
            do { try await lifecycle.shutdown(); try await coordinator.shutdown(); try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root) } catch { Issue.record(error) }
        }
        let registered = try await WatchRecordTests().register(value)
        let task = Task { try await driver.run(registered.id,force: true) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await preparation.running) {
            guard ContinuousClock.now < deadline else { task.cancel(); throw InvarError("TEST_DEADLINE","Watch preparation did not begin") }
            try await Task.sleep(for: .milliseconds(2))
        }
        _ = try await lifecycle.beginStop(registered.id,principal: registered.principal)
        task.cancel()
        do { try await task.value; Issue.record("Cancelled watch driver returned success") }
        catch is CancellationError {}
        #expect(!(await preparation.running))
        let id = WatchRequestIdentity.demandID(watchID: registered.id,generation: 1,operation: "plan.prepare")
        #expect(try await value.store.loadDemand(id).state == "cancelled")
        #expect(try await lifecycle.finishStop(registered.id).state == "stopped")
        #expect(await coordinator.activeCount == 0)
    }

}
