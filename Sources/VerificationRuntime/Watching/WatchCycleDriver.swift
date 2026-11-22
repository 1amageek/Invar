import Foundation
import VerificationCore

/// Drives one persisted watch generation through the shared operation coordinator.
actor WatchCycleDriver {
    private let repository: any VerificationRepository
    private let coordinator: any WorkspaceCoordinating
    private let probe: any WatchInputProbing
    private let lifecycle: WatchLifecycle
    private var running = Set<String>()
    init(repository: any VerificationRepository,coordinator: any WorkspaceCoordinating,probe: any WatchInputProbing,lifecycle: WatchLifecycle) {
        self.repository = repository; self.coordinator = coordinator; self.probe = probe; self.lifecycle = lifecycle
    }
    func run(_ id: String,force: Bool) async throws {
        guard running.insert(id).inserted else { throw InvarError("WATCH_BUSY","This watch already owns a cycle",exitCode: 6) }
        defer { running.remove(id) }
        do {
            try await drive(id,force: force)
        } catch {
            let original = error
            let watch: WatchRecord
            do {
                watch = try await repository.loadWatch(id)
                try await lifecycle.cancelChildren(watch)
            } catch { throw InvarError("CLEANUP_FAILED","Watch cycle failed (\(original)); child cleanup failed (\(error))",exitCode: 6) }
            if original is CancellationError { throw original }
            if watch.state == "active" {
                let current = try await repository.loadWatch(id)
                if current.state == "active" {
                    let failure = Self.failure(original)
                    let idle = current.revising(state: "active",cycle: WatchCycle(generation: current.cycle.generation),lastPlanID: current.cycle.planID,failure: failure)
                    try await repository.saveWatch(idle,expectedRevision: current.revision)
                }
            }
            throw original
        }
    }
    private func drive(_ id: String,force: Bool) async throws {
        try Task.checkCancellation()
        var watch = try await repository.loadWatch(id)
        if watch.cycle.phase == "idle" {
            if !force, let plan = watch.lastPlanID {
                let observed = try await probe.probe(configurationPath: watch.configurationPath,planID: plan,budget: watch.budget)
                if !observed.changed { return }
            }
            try Task.checkCancellation()
            let next = watch.revising(state: "active",cycle: WatchCycle(generation: watch.cycle.generation+1,phase: "preparing"))
            try await repository.saveWatch(next,expectedRevision: watch.revision); watch = next
        }
        if watch.cycle.phase == "preparing" {
            let operation = WorkspaceOperation.preparePlan(configurationPath: watch.configurationPath,changeRevisionID: nil,budget: watch.budget)
            let prepared = try await child(watch,operation: operation)
            guard prepared.state == "completed", let planID = prepared.resultID else { throw prepared.failure ?? InvarError("WATCH_PREPARATION_FAILED","Watch preparation did not complete",exitCode: 6) }
            let current = try await active(id,generation: watch.cycle.generation)
            let target = try await repository.schedulingPlan(planID)
            let reuse = try await canReassociate(current,target: target)
            let next = current.revising(state: "active",cycle: WatchCycle(generation: current.cycle.generation,phase: reuse ? "reconciling" : "verifying",planID: planID))
            try await repository.saveWatch(next,expectedRevision: current.revision); watch = next
        }
        guard let planID = watch.cycle.planID else { throw InvarError("STORE_INTEGRITY","Watch execution stage lost its prepared plan") }
        let operation: WorkspaceOperation
        if watch.cycle.phase == "reconciling" {
            guard let runID = watch.lastRunID else { throw InvarError("STORE_INTEGRITY","Watch reassociation lost its original run") }
            operation = .reconcile(planID: planID,runID: runID)
        } else if watch.cycle.phase == "verifying" { operation = .verify(planID: planID,changeRevisionID: nil,replayOfRunID: nil) }
        else { throw InvarError("STORE_INTEGRITY","Watch cycle has an unknown execution stage") }
        let result = try await child(watch,operation: operation)
        guard result.state == "completed", let resultID = result.resultID, let view = result.view else { throw result.failure ?? InvarError("WATCH_VERIFICATION_FAILED","Watch result has no completed committed view",exitCode: 6) }
        let current = try await active(id,generation: watch.cycle.generation)
        let runID = watch.cycle.phase == "verifying" ? resultID : current.lastRunID
        let idle = current.revising(state: "active",cycle: WatchCycle(generation: current.cycle.generation),lastPlanID: planID,lastRunID: runID,lastView: view)
        try await repository.saveWatch(idle,expectedRevision: current.revision)
    }
    private func canReassociate(_ watch: WatchRecord,target: SchedulingPlan) async throws -> Bool {
        guard let runID = watch.lastRunID else { return false }
        let run = try await repository.loadRun(runID), original = try await repository.schedulingPlan(run.planID)
        guard original.capturedScopeDigest == target.capturedScopeDigest, !run.attempts.isEmpty, run.attempts.allSatisfy({ $0.execution == "completed" }), run.attempts.count == target.jobs.count, Set(run.attempts.map(\.jobID)) == Set(target.jobs.map(\.id)) else { return false }
        _ = try EvidenceReconciliation.associations(run: run,original: original,target: target)
        return true
    }
    private func child(_ watch: WatchRecord,operation: WorkspaceOperation) async throws -> RunDemand {
        try Task.checkCancellation()
        _ = try await active(watch.id,generation: watch.cycle.generation)
        let id = WatchRequestIdentity.demandID(watchID: watch.id,generation: watch.cycle.generation,operation: operation.name)
        let retained: RunDemand?
        do { retained = try await repository.loadDemand(id) }
        catch let failure as InvarError where failure.code == "REQUEST_NOT_FOUND" { retained = nil }
        if let retained {
            guard retained.request == operation, retained.origin == "watch", retained.principal == watch.principal else { throw InvarError("STORE_INTEGRITY","Retained watch child differs from its fixed stage") }
        } else {
            let envelope = WatchRequestIdentity.envelopeID(watchID: watch.id,generation: watch.cycle.generation,operation: operation.name)
            guard try await repository.loadReceipt(envelope) == nil else { throw InvarError("STORE_INTEGRITY","Accepted watch receipt lost its original child") }
            let receipt = try await coordinator.submitWatch(watchID: watch.id,operation: operation)
            guard receipt.operationID == id else { throw InvarError("STORE_INTEGRITY","Watch acceptance changed its deterministic demand ID") }
        }
        let current = try await active(watch.id,generation: watch.cycle.generation)
        if current.cycle.pendingDemandID != id {
            let attached = current.revising(state: "active",cycle: WatchCycle(generation: current.cycle.generation,phase: current.cycle.phase,pendingDemandID: id,planID: current.cycle.planID))
            try await repository.saveWatch(attached,expectedRevision: current.revision)
        }
        while true {
            try Task.checkCancellation()
            let demand = try await coordinator.status(id,principal: watch.principal,administrative: false)
            if !["queued","running","cancelling"].contains(demand.state) { return demand }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
    private func active(_ id: String,generation: Int) async throws -> WatchRecord {
        try Task.checkCancellation()
        let value = try await repository.loadWatch(id)
        guard value.state == "active", value.cycle.generation == generation else { throw InvarError("WATCH_STOPPED","Watch admission or generation changed",exitCode: 6) }
        return value
    }
    private static func failure(_ error: any Error) -> InvarError {
        if let failure = error as? InvarError { return InvarError(failure.code,String(failure.message.prefix(256)),exitCode: failure.exitCode) }
        return InvarError("WATCH_FAILED",String(String(describing: error).prefix(256)),exitCode: 7)
    }
}
