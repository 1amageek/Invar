import Foundation
import VerificationCore

extension SQLiteVerificationStore {
    public func beginWatchStop(_ id: String,principal: String,target: String) throws -> WatchRecord {
        try ensureAccepting()
        guard ["stopped","expired"].contains(target) else { throw InvarError("INVALID_REQUEST","Unknown watch stop target") }
        return try transaction(usingFailureReserve: true) {
            let current = try loadWatch(id)
            guard current.principal == principal else { throw InvarError("POLICY_DENIED","Only the original principal may stop its watch",exitCode: 8) }
            guard target != "expired" || current.expiresAt <= Date().timeIntervalSince1970 else { throw InvarError("INVALID_REQUEST","Watch expiration has not occurred") }
            if ["stopped","expired","stopping"].contains(current.state) { return current }
            guard current.state != "registering" else { throw InvarError("CLEANUP_PENDING","The registration demand must finish cancellation before stopping",exitCode: 6) }
            let next = current.revising(state: "stopping",stopTarget: target)
            try saveWatch(next,expectedRevision: current.revision)
            return next
        }
    }
    public func finishWatchPause(_ id: String) throws -> WatchRecord {
        try ensureAccepting()
        return try transaction(usingFailureReserve: true) {
            let current = try loadWatch(id)
            guard current.state == "paused" else { return current }
            var candidates = current.cycle.pendingDemandID.map { [$0] } ?? []
            for operation in ["plan.prepare","verification.run","verification.reconcile"] {
                candidates.append(WatchRequestIdentity.demandID(watchID: id,generation: current.cycle.generation,operation: operation))
            }
            for childID in Set(candidates) where try database.head("demand",id: childID) != nil {
                let child = try loadDemand(childID)
                guard !["queued","running","cancelling"].contains(child.state) else { throw InvarError("CLEANUP_PENDING","Paused watch still owns a live child") }
            }
            if current.cycle.phase == "idle", current.cycle.pendingDemandID == nil { return current }
            let next = current.revising(state: "paused",cycle: WatchCycle(generation: current.cycle.generation),failure: current.failure)
            try saveWatch(next,expectedRevision: current.revision)
            return next
        }
    }
    public func pauseWatch(_ id: String,failure: InvarError) throws -> WatchRecord {
        try ensureAccepting()
        return try transaction(usingFailureReserve: true) {
            let current = try loadWatch(id)
            if current.state != "active" { return current }
            let next = current.revising(state: "paused",failure: failure)
            try saveWatch(next,expectedRevision: current.revision)
            return next
        }
    }
    public func loadWatch(_ id: String) throws -> WatchRecord {
        try ensureAccepting(); try safeID(id)
        guard let head = try database.head("watch",id: id), let bytes = try database.load("watch",id: head.recordID) else { throw InvarError("WATCH_NOT_FOUND","Unknown durable watch") }
        let value = try JSONDecoder().decode(WatchRecord.self,from: bytes)
        guard value.id == id, value.revision == head.revision, value.state == head.state else { throw InvarError("STORE_INTEGRITY","Watch head differs from retained revision") }
        return value
    }
    public func watches(states: [String]) throws -> [WatchRecord] {
        try ensureAccepting()
        guard !states.isEmpty, states.count <= 6, Set(states).isSubset(of: ["registering","active","paused","stopping","stopped","expired"]) else { throw InvarError("INVALID_REQUEST","Invalid watch state selection") }
        let rows = try database.current("watch",states: states,limit: 32,maximumBytes: 32 * 16384)
        return try rows.map { try JSONDecoder().decode(WatchRecord.self,from: $0) }
    }
    public func createWatch(_ value: WatchRecord) throws {
        try ensureAccepting(); try validateWatch(value)
        guard value.revision == 1, value.state == "registering", value.cycle == WatchCycle(), value.lastPlanID == nil, value.lastRunID == nil, value.lastView == nil, value.failure == nil else { throw InvarError("INVALID_REQUEST","New watch must have no prior cycle or result") }
        try transaction {
            guard try database.head("watch",id: value.id) == nil else { throw InvarError("IDEMPOTENCY_CONFLICT","Watch is already registered") }
            let demand = try loadDemand(value.id), envelope = try loadEnvelope(value.envelopeID)
            guard case .watch(let path,let budget) = demand.request, demand.state == "running", demand.envelopeID == value.envelopeID, demand.principal == value.principal,
                envelope.principal == value.principal, envelope.workspaceID == value.workspaceID,
                path == value.configurationPath, budget == value.budget else { throw InvarError("POLICY_DENIED","Registration differs from its original running watch demand",exitCode: 8) }
            guard try watches(states: ["registering","active","paused","stopping"]).count < 32 else { throw InvarError("RESOURCE_LIMIT","Watch registration capacity exhausted",exitCode: 6) }
            try insertWatch(value,expectedRevision: 0)
        }
    }
    public func saveWatch(_ value: WatchRecord,expectedRevision: Int) throws {
        try updateWatch(value,expectedRevision: expectedRevision,completingRegistration: false)
    }
    private func updateWatch(_ value: WatchRecord,expectedRevision: Int,completingRegistration: Bool) throws {
        try ensureAccepting(); try validateWatch(value)
        try transaction(usingFailureReserve: value.state != "active") {
            let previous = try loadWatch(value.id)
            guard previous.revision == expectedRevision, value.revision == expectedRevision+1 else { throw InvarError("REVISION_CONFLICT","Watch revision changed") }
            guard previous.envelopeID == value.envelopeID, previous.workspaceID == value.workspaceID, previous.principal == value.principal,
                previous.configurationPath == value.configurationPath, previous.budget == value.budget, previous.expiresAt == value.expiresAt,
                ["registering","active","paused","stopping"].contains(previous.state) else { throw InvarError("INVALID_TRANSITION","Watch authority is fixed and stop/expiry is terminal") }
            if previous.state == "registering" {
                guard ["stopped","expired"].contains(value.state) || completingRegistration && value.state == "active" else { throw InvarError("INVALID_TRANSITION","Registration activation belongs to its parent terminal transaction") }
            }
            guard value.cycle.generation == previous.cycle.generation || previous.cycle.phase == "idle" && value.cycle.generation == previous.cycle.generation+1 && value.cycle.phase == "preparing" else { throw InvarError("INVALID_TRANSITION","Watch generation can advance only from an idle boundary") }
            guard value.state != "stopping" || value.stopTarget != "expired" || value.expiresAt <= Date().timeIntervalSince1970 else { throw InvarError("INVALID_TRANSITION","Watch expiration has not occurred") }
            if previous.state == "stopping" {
                guard ["stopping",previous.stopTarget].compactMap({ $0 }).contains(value.state), value.stopTarget == previous.stopTarget else { throw InvarError("INVALID_TRANSITION","An owned stop cannot reopen or change its target") }
            }
            if ["stopped","expired"].contains(value.state) {
                guard value.cycle.phase == "idle", value.cycle.pendingDemandID == nil, value.state != "expired" || value.expiresAt <= Date().timeIntervalSince1970 else { throw InvarError("INVALID_TRANSITION","Terminal watch must finish cleanup and its expiry must be real") }
                var candidates = [previous.cycle.pendingDemandID].compactMap { $0 }
                for operation in ["plan.prepare","verification.run","verification.reconcile"] {
                    candidates.append(WatchRequestIdentity.demandID(watchID: value.id,generation: previous.cycle.generation,operation: operation))
                }
                for id in Set(candidates) {
                    if try database.head("demand",id: id) != nil {
                        let child = try loadDemand(id)
                        guard !["queued","running","cancelling"].contains(child.state) else { throw InvarError("CLEANUP_PENDING","Watch child has not reached terminal cleanup",exitCode: 6) }
                    }
                }
            }
            try insertWatch(value,expectedRevision: expectedRevision)
        }
    }
    func completeWatchRegistration(_ id: String,demand: RunDemand) throws {
        guard database.inTransaction else { throw InvarError("INVALID_TRANSITION","Watch activation requires the parent commit transaction") }
        let watch = try loadWatch(id)
        guard watch.state == "registering", watch.id == demand.id, watch.envelopeID == demand.envelopeID, watch.principal == demand.principal else { throw InvarError("INVALID_RESULT","Watch activation differs from its original registration") }
        let active = watch.revising(state: "active")
        try updateWatch(active,expectedRevision: watch.revision,completingRegistration: true)
    }
    func abortWatchRegistration(_ demand: RunDemand) throws {
        guard case .watch = demand.request, try database.head("watch",id: demand.id) != nil else { return }
        let watch = try loadWatch(demand.id)
        if watch.state != "registering" { return }
        guard watch.envelopeID == demand.envelopeID, watch.principal == demand.principal else { throw InvarError("STORE_INTEGRITY","Staged watch belongs to another original request") }
        let stopped = watch.revising(state: "stopped",failure: demand.failure)
        try saveWatch(stopped,expectedRevision: watch.revision)
    }
    private func validateWatch(_ value: WatchRecord) throws {
        try safeID(value.id); try safeID(value.envelopeID); _ = try Canonical.relative(value.configurationPath); try PlanValidation.budget(value.budget)
        guard value.revision > 0, value.revision < Int.max, value.cycle.generation >= 0, value.cycle.generation < Int.max,
            ["registering","active","paused","stopping","stopped","expired"].contains(value.state),
            value.state != "registering" || value.revision == 1 && value.cycle == WatchCycle() && value.lastPlanID == nil && value.lastRunID == nil && value.lastView == nil && value.failure == nil,
            value.state != "stopping" || value.stopTarget == "stopped" || value.stopTarget == "expired",
            !["active","paused"].contains(value.state) || value.stopTarget == nil,
            !["stopped","expired"].contains(value.state) || value.stopTarget == nil || value.stopTarget == value.state,
            ["idle","preparing","verifying","reconciling"].contains(value.cycle.phase),
            value.cycle.phase != "idle" || value.cycle.pendingDemandID == nil,
            !["verifying","reconciling"].contains(value.cycle.phase) || value.cycle.planID != nil,
            value.expiresAt.isFinite,
            (value.failure?.message.utf8.count ?? 0) <= 1024, (value.failure?.code.utf8.count ?? 0) <= 128 else { throw InvarError("INVALID_REQUEST","Invalid watch scope/state bounds") }
        let bytes = try Canonical.encode(value)
        guard bytes.count <= 16384 else { throw InvarError("RESOURCE_LIMIT","Watch metadata exceeds16 KiB",exitCode: 6) }
    }
    private func insertWatch(_ value: WatchRecord,expectedRevision: Int) throws {
        let row = Canonical.parts("invar.watch-revision/2",[value.id,String(value.revision)])
        let bytes = try Canonical.encode(value)
        try database.insert("watch",id: row,bytes: bytes)
        try database.advance("watch",id: value.id,expectedRevision: expectedRevision,recordID: row,state: value.state)
        try database.link(ownerKind: "watch",ownerID: row,targetKind: "envelope",targetID: value.envelopeID)
        try database.link(ownerKind: "watch",ownerID: row,targetKind: "principalIdentity",targetID: value.principal)
        for id in [value.cycle.planID,value.lastPlanID].compactMap({ $0 }) {
            let plan = try schedulingPlan(id)
            guard plan.input.workspaceID == value.workspaceID else { throw InvarError("INPUT_MISMATCH","Watch plan belongs to another workspace") }
            try database.link(ownerKind: "watch",ownerID: row,targetKind: "plan",targetID: id)
        }
        if let id = value.cycle.pendingDemandID {
            let demand = try loadDemand(id)
            guard demand.principal == value.principal else { throw InvarError("POLICY_DENIED","Watch cannot own another principal's demand",exitCode: 8) }
            switch (value.cycle.phase,demand.request) {
            case ("preparing",.preparePlan(let path,let change,let budget)):
                guard path == value.configurationPath, change == nil, budget == value.budget else { throw InvarError("INPUT_MISMATCH","Watch preparation differs from its fixed configuration/budget") }
            case ("verifying",.verify(let plan,let change,let replay,nil)):
                guard value.cycle.planID == plan, change == nil, replay == nil else { throw InvarError("INPUT_MISMATCH","Watch verification differs from its prepared plan") }
            case ("reconciling",.reconcile(let plan,let run)):
                guard value.cycle.planID == plan, value.lastRunID == run else { throw InvarError("INPUT_MISMATCH","Watch reassociation differs from its original run/prepared plan") }
            default: throw InvarError("INVALID_TRANSITION","Watch phase cannot own this operation")
            }
            try database.link(ownerKind: "watch",ownerID: row,targetKind: "demand",targetID: id)
        }
        if let id = value.lastRunID {
            let run = try loadRun(id), plan = try schedulingPlan(run.planID)
            guard plan.input.workspaceID == value.workspaceID else { throw InvarError("INPUT_MISMATCH","Watch run belongs to another workspace") }
            try database.link(ownerKind: "watch",ownerID: row,targetKind: "run",targetID: id)
        }
        if let reference = value.lastView {
            let view = try loadView(reference.id), actual = try view.reference()
            guard actual == reference, actual.workspaceID == value.workspaceID else { throw InvarError("INPUT_MISMATCH","Watch view reference differs") }
            try database.link(ownerKind: "watch",ownerID: row,targetKind: "view",targetID: reference.id)
        }
    }
}
