import Foundation
import VerificationCore

extension SQLiteVerificationStore {
    public func authorizeWatch(_ id: String) throws {
        try ensureAccepting()
        let watch = try loadWatch(id)
        guard watch.state == "active" else { throw InvarError("POLICY_DENIED","Watch is not active",exitCode: 8) }
        _ = try watchAuthority(watch)
    }
    public func issueWatchEnvelope(watchID: String,operation: WorkspaceOperation,epoch: String,now: Double) throws -> RequestEnvelope {
        try ensureAccepting()
        return try transaction {
            let watch = try loadWatch(watchID)
            _ = try watchAuthority(watch)
            try validateWatchOperation(watch,operation: operation)
            guard let host = try loadPolicy() else { throw InvarError("POLICY_DENIED","Watch host policy is unavailable",exitCode: 8) }
            let key = WatchRequestIdentity.key(watchID: watch.id,generation: watch.cycle.generation,operation: operation.name)
            let id = WatchRequestIdentity.envelopeID(watchID: watch.id,generation: watch.cycle.generation,operation: operation.name)
            let expiry = min(now+min(watch.budget.runTimeoutSeconds,host.maximumEnvelopeSeconds),watch.expiresAt)
            let fingerprint = try Canonical.identity(operation)
            let proposed = RequestEnvelope(id: id,watchID: watch.id,capabilities: watch.capabilities,requestKey: key,principal: watch.principal,workspaceID: watch.workspaceID,fingerprint: fingerprint,operation: operation.name,daemonEpoch: epoch,policyRevision: watch.policyRevision,expiresAt: expiry,retainUntil: now+policy.retentionSeconds)
            try validateEnvelopeLifetime(proposed,now: now)
            let envelope = try insertEnvelope(proposed,now: now)
            try validateWatchRequest(envelope,operation: operation,now: now)
            let row = Canonical.parts("invar.watch-revision/2",[watch.id,String(watch.revision)])
            try database.link(ownerKind: "watch",ownerID: row,targetKind: "envelope",targetID: envelope.id)
            return envelope
        }
    }
    public func validateWatchRequest(_ envelope: RequestEnvelope,operation: WorkspaceOperation,now: Double) throws {
        try ensureAccepting()
        guard now.isFinite, let id = envelope.watchID, envelope.sessionID == nil, envelope.expiresAt > now else { throw InvarError("POLICY_DENIED","Watch envelope has no fixed unexpired owner",exitCode: 8) }
        let watch = try loadWatch(id)
        _ = try watchAuthority(watch)
        try validateWatchOperation(watch,operation: operation)
        let original = try loadEnvelope(envelope.id), fingerprint = try Canonical.identity(operation)
        let expectedID = WatchRequestIdentity.envelopeID(watchID: watch.id,generation: watch.cycle.generation,operation: operation.name)
        let demandID = Canonical.parts("invar.operation/2",[envelope.id])
        guard original == envelope, envelope.id == expectedID, envelope.fingerprint == fingerprint, envelope.operation == operation.name,
            envelope.principal == watch.principal, envelope.workspaceID == watch.workspaceID, envelope.policyRevision == watch.policyRevision,
            Set(envelope.capabilities) == Set(watch.capabilities), envelope.expiresAt <= watch.expiresAt,
            watch.cycle.pendingDemandID == nil || watch.cycle.pendingDemandID == demandID else { throw InvarError("POLICY_DENIED","Watch request differs from its original stage/authority",exitCode: 8) }
    }
    private func validateWatchOperation(_ value: WatchRecord,operation: WorkspaceOperation) throws {
        guard value.state == "active", value.expiresAt > Date().timeIntervalSince1970 else { throw InvarError("POLICY_DENIED","Watch admission is stopped, paused or expired",exitCode: 8) }
        switch (value.cycle.phase,operation) {
        case ("preparing",.preparePlan(let path,let change,let budget)):
            guard path == value.configurationPath, change == nil, budget == value.budget else { throw InvarError("POLICY_DENIED","Preparation exceeds fixed watch configuration/budget",exitCode: 8) }
        case ("verifying",.verify(let planID,let change,let replay,nil)):
            guard value.cycle.planID == planID, change == nil, replay == nil else { throw InvarError("POLICY_DENIED","Verification exceeds the prepared watch plan",exitCode: 8) }
            try completedWatchPreparation(value,planID: planID)
            let plan = try schedulingPlan(planID)
            guard plan.input.workspaceID == value.workspaceID, plan.budget == value.budget else { throw InvarError("INPUT_MISMATCH","Watch plan differs from its workspace/budget") }
        case ("reconciling",.reconcile(let planID,let runID)):
            guard value.cycle.planID == planID, value.lastRunID == runID else { throw InvarError("POLICY_DENIED","Reassociation exceeds the original watch evidence",exitCode: 8) }
            try completedWatchPreparation(value,planID: planID)
            let target = try schedulingPlan(planID), run = try loadRun(runID), original = try schedulingPlan(run.planID)
            _ = try EvidenceReconciliation.associations(run: run,original: original,target: target)
        default: throw InvarError("POLICY_DENIED","Operation is not the currently admitted watch stage",exitCode: 8)
        }
    }
    private func completedWatchPreparation(_ value: WatchRecord,planID: String) throws {
        let id = WatchRequestIdentity.demandID(watchID: value.id,generation: value.cycle.generation,operation: "plan.prepare")
        let preparation: RunDemand
        do { preparation = try loadDemand(id) }
        catch let failure as InvarError where failure.code == "REQUEST_NOT_FOUND" {
            throw InvarError("POLICY_DENIED","Watch stage lacks this cycle's completed fixed preparation",exitCode: 8)
        }
        guard preparation.origin == "watch", preparation.principal == value.principal, preparation.state == "completed", preparation.resultID == planID,
            case .preparePlan(let path,let change,let budget) = preparation.request, path == value.configurationPath, change == nil, budget == value.budget else {
            throw InvarError("POLICY_DENIED","Watch stage lacks this cycle's completed fixed preparation",exitCode: 8)
        }
    }

}
