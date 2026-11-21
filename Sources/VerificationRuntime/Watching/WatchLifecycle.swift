import Foundation
import VerificationCore

/// Owns registration/stop records; the registry separately owns monitoring tasks.
actor WatchLifecycle {
    private let repository: any VerificationRepository
    private let coordinator: any WorkspaceCoordinating
    private var registrationClosed = false
    private var stopped = false
    private var finalizers: [String:Task<WatchRecord,any Error>] = [:]
    init(repository: any VerificationRepository,coordinator: any WorkspaceCoordinating) { self.repository = repository; self.coordinator = coordinator }
    func prepareRegistration(_ demand: RunDemand,authority: OperationAuthority) async throws -> String {
        guard !registrationClosed, !stopped, authority.principal == demand.principal, authority.capabilities.isSuperset(of: [.watching,.planning,.verification]),
            case .watch(let path,let budget) = demand.request else { throw InvarError("POLICY_DENIED","Watch registration exceeds its original operation authority",exitCode: 8) }
        let envelope = try await repository.loadEnvelope(demand.envelopeID)
        guard envelope.sessionID != nil, envelope.watchID == nil, envelope.policyRevision == authority.policyRevision,
            let principal = try await repository.principal(identity: demand.principal) else { throw InvarError("POLICY_DENIED","Watch registration lacks its original authenticated principal",exitCode: 8) }
        let ceiling = Set(envelope.capabilities).intersection(authority.capabilities)
        guard ceiling.isSuperset(of: [.watching,.planning,.verification]) else { throw InvarError("POLICY_DENIED","Original session did not grant planning/verification/watching",exitCode: 8) }
        try Task.checkCancellation()
        let record = WatchRecord(id: demand.id,envelopeID: demand.envelopeID,workspaceID: envelope.workspaceID,principal: authority.principal,policyRevision: authority.policyRevision,capabilities: Array(ceiling),configurationPath: path,budget: budget,expiresAt: principal.expiresAt)
        try await repository.createWatch(record)
        try Task.checkCancellation()
        // Only the coordinator's parent terminal transaction activates this record.
        return record.id
    }
    func beginStop(_ id: String,principal: String,target: String = "stopped") async throws -> WatchRecord {
        guard !stopped else { throw InvarError("COORDINATOR_STOPPED","Watch lifecycle is closed") }
        guard ["stopped","expired"].contains(target) else { throw InvarError("INVALID_REQUEST","Unknown watch stop target") }
        var watch = try await repository.loadWatch(id)
        guard watch.principal == principal else { throw InvarError("POLICY_DENIED","A principal may stop only its own watch",exitCode: 8) }
        guard target != "expired" || watch.expiresAt <= Date().timeIntervalSince1970 else { throw InvarError("INVALID_REQUEST","Watch expiration has not occurred") }
        if watch.state == "registering" {
            try await coordinator.cancel(watch.id,principal: principal,administrative: false)
            watch = try await repository.loadWatch(id)
        }
        return try await repository.beginWatchStop(id,principal: principal,target: target)
    }
    /// The registry drains its nondurable probe/cycle tasks before this call.
    func finishStop(_ id: String) async throws -> WatchRecord {
        if let task = finalizers[id] { return try await task.value }
        guard !stopped else { throw InvarError("COORDINATOR_STOPPED","Watch lifecycle is closed") }
        let task = Task { try await self.finish(id) }
        finalizers[id] = task
        defer { finalizers.removeValue(forKey: id) }
        return try await task.value
    }
    private func finish(_ id: String) async throws -> WatchRecord {
        var watch = try await repository.loadWatch(id)
        if ["stopped","expired"].contains(watch.state) { return watch }
        guard watch.state == "stopping", let target = watch.stopTarget else { throw InvarError("INVALID_TRANSITION","Stop was not durably requested") }
        try await cancelChildren(watch)
        watch = try await repository.loadWatch(id)
        if ["stopped","expired"].contains(watch.state) { return watch }
        guard watch.state == "stopping", watch.stopTarget == target else { throw InvarError("INVALID_TRANSITION","Stop target changed during cleanup") }
        let terminal = watch.revising(state: target,cycle: WatchCycle(generation: watch.cycle.generation))
        try await repository.saveWatch(terminal,expectedRevision: watch.revision)
        return terminal
    }
    func cancelChildren(_ watch: WatchRecord) async throws {
        var children: [String:String] = [:]
        for operation in ["plan.prepare","verification.run","verification.reconcile"] {
            let envelopeID = WatchRequestIdentity.envelopeID(watchID: watch.id,generation: watch.cycle.generation,operation: operation)
            let id = WatchRequestIdentity.demandID(watchID: watch.id,generation: watch.cycle.generation,operation: operation)
            children[id] = envelopeID
        }
        var ids = Set(children.keys)
        if let pending = watch.cycle.pendingDemandID { ids.insert(pending) }
        for id in ids {
            let envelope = children[id]
            let demand: RunDemand
            do { demand = try await repository.loadDemand(id) }
            catch let error as InvarError where error.code == "REQUEST_NOT_FOUND" {
                if id == watch.cycle.pendingDemandID { throw InvarError("STORE_INTEGRITY","Recorded watch child is missing") }
                if let envelope, try await repository.loadReceipt(envelope) != nil { throw InvarError("STORE_INTEGRITY","Accepted watch receipt lost its demand") }
                // A missing deterministic child without a receipt was never accepted.
                continue
            }
            guard demand.principal == watch.principal else { throw InvarError("STORE_INTEGRITY","Watch cleanup found another principal's child") }
            try await coordinator.cancel(id,principal: watch.principal,administrative: false)
        }
    }
    func closeAdmission() { registrationClosed = true }
    func shutdown() async throws {
        registrationClosed = true; stopped = true
        let tasks = Array(finalizers.values)
        for task in tasks { _ = try await task.value }
    }
}
