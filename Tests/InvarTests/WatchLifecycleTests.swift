import Foundation
import Testing
import VerificationCore
import VerificationStore
@testable import VerificationRuntime

@Suite(.timeLimit(.minutes(1))) struct WatchLifecycleTests {
    actor Preparation: WorkspaceOperationExecuting {
        private(set) var running = false
        func execute(_ demand: RunDemand) async throws -> String {
            running = true; defer { running = false }
            try await Task.sleep(for: .seconds(30))
            throw InvarError("TEST_DEADLINE","Fixture preparation must be cancelled")
        }
    }
    @Test func stagedRegistrationAndExplicitStopPreserveWatchLifecycle() async throws {
        let value = try await WatchRecordTests().fixture()
        let scheduler = VerificationScheduler(backend: SchedulerTests.ResourceFailure(),repository: value.store)
        let coordinator = WorkspaceCoordinator(repository: value.store,scheduler: scheduler,operations: DurableCoordinatorTests.Operations(),epoch: value.epoch,maximumDemands: 8)
        let lifecycle = WatchLifecycle(repository: value.store,coordinator: coordinator)
        defer {
            do { try await lifecycle.shutdown(); try await coordinator.shutdown(); try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root) } catch { Issue.record(error) }
        }
        let parent = try await value.store.loadDemand(value.record.id)
        let id = try await lifecycle.prepareRegistration(parent)
        #expect(try await value.store.loadWatch(id).state == "registering")
        try await value.store.completeDemand(parent.transitioning(to: "completed",resultID: id),run: nil,view: nil,expectedRevision: parent.revision)
        #expect(try await value.store.loadWatch(id).state == "active")
        await #expect(throws: InvarError.self) { try await lifecycle.beginStop(id,principal: parent.principal,target: "expired") }
        #expect(try await value.store.loadWatch(id).state == "active")
        #expect(try await lifecycle.beginStop(id,principal: parent.principal).state == "stopping")
        #expect(try await lifecycle.finishStop(id).state == "stopped")
        #expect(try await lifecycle.finishStop(id).state == "stopped")
    }
    @Test func stopFindsAcceptedChildBeforePendingPointerAndAwaitsItsActualTaskCleanup() async throws {
        let value = try await WatchRecordTests().fixture()
        let scheduler = VerificationScheduler(backend: SchedulerTests.ResourceFailure(),repository: value.store), preparation = Preparation()
        let coordinator = WorkspaceCoordinator(repository: value.store,scheduler: scheduler,operations: preparation,epoch: value.epoch,maximumDemands: 8)
        let lifecycle = WatchLifecycle(repository: value.store,coordinator: coordinator)
        defer {
            do { try await lifecycle.shutdown(); try await coordinator.shutdown(); try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root) } catch { Issue.record(error) }
        }
        let parent = try await value.store.loadDemand(value.record.id)
        let id = try await lifecycle.prepareRegistration(parent)
        try await value.store.completeDemand(parent.transitioning(to: "completed",resultID: id),run: nil,view: nil,expectedRevision: parent.revision)
        let active = try await value.store.loadWatch(id), cycle = active.revising(state: "active",cycle: WatchCycle(generation: 1,phase: "preparing"))
        try await value.store.saveWatch(cycle,expectedRevision: active.revision)
        let operation = WorkspaceOperation.preparePlan(configurationPath: cycle.configurationPath,changeRevisionID: nil,budget: cycle.budget)
        let receipt = try await coordinator.submitWatch(watchID: id,operation: operation)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await preparation.running) {
            guard ContinuousClock.now < deadline else { throw InvarError("TEST_DEADLINE","Derived preparation did not start") }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(try await value.store.loadWatch(id).cycle.pendingDemandID == nil)
        _ = try await lifecycle.beginStop(id,principal: parent.principal)
        let stopped = try await lifecycle.finishStop(id)
        #expect(stopped.state == "stopped" && stopped.cycle.pendingDemandID == nil)
        #expect(!(await preparation.running))
        #expect(try await value.store.loadDemand(receipt.operationID).state == "cancelled")
        #expect(await coordinator.activeCount == 0)
    }
}
