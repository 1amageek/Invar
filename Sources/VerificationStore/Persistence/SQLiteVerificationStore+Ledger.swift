import Foundation
import VerificationCore

extension SQLiteVerificationStore {
    public func loadDescriptor(_ id: String) throws -> JobDescriptor {
        try ensureAccepting(); try safeID(id)
        guard let bytes = try database.load("descriptor",id: id) else { throw InvarError("DESCRIPTOR_NOT_FOUND","Unknown job descriptor") }
        let value = try JSONDecoder().decode(JobDescriptor.self,from: bytes)
        try PlanValidation.descriptor(value)
        guard try value.identity() == id else { throw InvarError("STORE_INTEGRITY","Descriptor digest differs") }
        return value
    }
    public func reusableEvidence(key: String) throws -> VerificationEvidence? {
        try ensureAccepting(); try safeID(key)
        guard let head = try database.head("executionCache",id: key) else { return nil }
        guard let bytes = try database.load("executionCache",id: head.recordID) else { throw InvarError("STORE_INTEGRITY","Execution cache row is missing") }
        let reference = try JSONDecoder().decode([String:String].self,from: bytes)
        guard reference["key"] == key, let evidenceID = reference["evidenceID"] else { throw InvarError("STORE_INTEGRITY","Invalid execution cache binding") }
        let evidence = try loadEvidence(evidenceID)
        guard evidence.executionKey == key, evidence.execution == "completed", let id = evidence.descriptorID else { throw InvarError("STORE_INTEGRITY","Execution cache differs from immutable evidence") }
        let job = try jobReference(id)
        guard job.executionKey == key else { throw InvarError("STORE_INTEGRITY","Execution cache has an incomplete or changed scope") }
        return evidence
    }
    public func activateEpoch(_ epoch: String,engineIdentity: String) throws {
        try ensureAccepting()
        try safeID(epoch); try safeID(engineIdentity)
        try transaction(usingFailureReserve: true) {
            let head = try database.head("epoch",id: "active")
            let revision = head?.revision ?? 0
            let value = try Canonical.encode(["epoch":epoch,"engineIdentity":engineIdentity])
            try database.insert("epoch",id: epoch,bytes: value)
            try database.advance("epoch",id: "active",expectedRevision: revision,recordID: epoch)
            if let head, head.recordID != epoch { try database.removeRecord("epoch",id: head.recordID) }
        }
        activeEpoch = epoch
    }
    public func loadEnvelope(_ id: String) throws -> RequestEnvelope {
        try ensureAccepting(); try safeID(id)
        guard let bytes = try database.load("envelope",id: id) else { throw InvarError("REQUEST_NOT_FOUND","Unknown fixed request envelope") }
        let value = try JSONDecoder().decode(RequestEnvelope.self,from: bytes)
        guard value.id == id else { throw InvarError("STORE_INTEGRITY","Request envelope ID differs") }
        return value
    }
    public func issueEnvelope(_ envelope: RequestEnvelope,now: Double) throws -> RequestEnvelope {
        try ensureAccepting()
        guard envelope.watchID == nil else { throw InvarError("POLICY_DENIED","Watch envelopes require the retained watch issuer",exitCode: 8) }
        try validateEnvelopeLifetime(envelope,now: now)
        return try insertEnvelope(envelope,now: now)
    }
    func validateEnvelopeLifetime(_ envelope: RequestEnvelope,now: Double) throws {
        try safeID(envelope.id)
        guard now.isFinite, envelope.daemonEpoch == activeEpoch, envelope.expiresAt.isFinite, envelope.retainUntil.isFinite, envelope.expiresAt > now,
            envelope.retainUntil >= envelope.expiresAt, envelope.retainUntil-now <= policy.retentionSeconds,
            !envelope.requestKey.isEmpty, envelope.requestKey.utf8.count <= 128, envelope.fingerprint.utf8.count == 64,
            !envelope.principal.isEmpty else { throw InvarError("REQUEST_EXPIRED","Envelope exceeds its fixed lifetime/scope bounds") }
    }
    func insertEnvelope(_ envelope: RequestEnvelope,now: Double) throws -> RequestEnvelope {
        let key = Canonical.parts("invar.envelope-key/2",[envelope.principal,envelope.workspaceID,envelope.requestKey])
        return try transaction {
            if let existing = try database.head("envelope",id: key), let bytes = try database.load("envelope",id: existing.recordID) {
                let recorded = try JSONDecoder().decode(RequestEnvelope.self,from: bytes)
                guard recorded.fingerprint == envelope.fingerprint, recorded.operation == envelope.operation, recorded.watchID == envelope.watchID else { throw InvarError("IDEMPOTENCY_CONFLICT","Request key has a different typed fingerprint") }
                guard recorded.expiresAt > now, recorded.daemonEpoch == activeEpoch else { throw InvarError("REQUEST_EXPIRED","Original request deadline cannot be renewed") }
                return recorded
            }
            let bytes = try Canonical.encode(envelope)
            try database.insert("envelope",id: envelope.id,bytes: bytes)
            try database.advance("envelope",id: key,expectedRevision: 0,recordID: envelope.id)
            return envelope
        }
    }
    public func acceptDemand(_ envelope: RequestEnvelope,demand: RunDemand,now: Double) throws -> OperationReceipt {
        try ensureAccepting()
        return try transaction {
            let supplied = try Canonical.encode(envelope)
            guard try database.load("envelope",id: envelope.id) == supplied, envelope.daemonEpoch == activeEpoch, envelope.expiresAt > now else { throw InvarError("REQUEST_EXPIRED","Missing, changed, expired or old-epoch request envelope") }
            if envelope.watchID != nil {
                try validateWatchRequest(envelope,operation: demand.request,now: now)
                guard demand.id == Canonical.parts("invar.operation/2",[envelope.id]) else { throw InvarError("REQUEST_MISMATCH","Watch child differs from deterministic accepted operation") }
            }
            let fingerprint = try Canonical.identity(demand.request)
            guard fingerprint == envelope.fingerprint else { throw InvarError("REQUEST_MISMATCH","Typed operation differs from accepted fingerprint") }
            if let receipt = try loadReceipt(envelope.id) {
                guard receipt.fingerprint == envelope.fingerprint, receipt.operationID == demand.id else { throw InvarError("IDEMPOTENCY_CONFLICT","Accepted request identifies a different operation") }
                return receipt
            }
            guard demand.envelopeID == envelope.id, demand.principal == envelope.principal, demand.origin == (envelope.watchID == nil ? "internal" : "watch"), demand.operation == envelope.operation else { throw InvarError("POLICY_DENIED","Demand does not match sealed request") }
            let receipt = OperationReceipt(id: envelope.id,operationID: demand.id,fingerprint: envelope.fingerprint,acceptedAt: now,daemonEpoch: envelope.daemonEpoch)
            try insertNewDemand(demand)
            let bytes = try Canonical.encode(receipt)
            try database.insert("operationReceipt",id: receipt.id,bytes: bytes)
            try database.link(ownerKind: "envelope",ownerID: envelope.id,targetKind: "operationReceipt",targetID: receipt.id)
            try database.link(ownerKind: "operationReceipt",ownerID: receipt.id,targetKind: "demand",targetID: demand.id)
            return receipt
        }
    }
    public func acceptExternalDemand(_ receipt: OperationReceipt,demand: RunDemand,actionID: String) throws {
        try ensureAccepting()
        try transaction {
            guard let base = try providerAction(actionID) else { throw InvarError("ACTION_NOT_FOUND","External admission lacks a durable preflight") }
            let mapping = try providerActionState(actionID), envelope = try loadEnvelope(base.envelope.id)
            guard mapping.state == "accepted", mapping.jobID == receipt.operationID,
                demand.origin == "provider", receipt.operationID == demand.id, receipt.id == envelope.id,
                receipt.daemonEpoch == activeEpoch, envelope.daemonEpoch == activeEpoch, envelope == base.envelope,
                receipt.fingerprint == envelope.fingerprint, demand.envelopeID == envelope.id, demand.principal == envelope.principal,
                demand.request == base.operation, envelope.expiresAt > Date().timeIntervalSince1970 else { throw InvarError("POLICY_DENIED","External receipt/authority mapping differs or expired") }
            guard try loadReceipt(receipt.id) == nil else { throw InvarError("IDEMPOTENCY_CONFLICT","External receipt is already mapped") }
            try insertNewDemand(demand)
            let bytes = try Canonical.encode(receipt)
            try database.insert("operationReceipt",id: receipt.id,bytes: bytes)
            try database.link(ownerKind: "envelope",ownerID: envelope.id,targetKind: "operationReceipt",targetID: receipt.id)
            try database.link(ownerKind: "operationReceipt",ownerID: receipt.id,targetKind: "demand",targetID: demand.id)
            let link = try Canonical.encode(["actionID":actionID])
            try database.insert("providerActionDemand",id: demand.id,bytes: link)
            try database.link(ownerKind: "demand",ownerID: demand.id,targetKind: "providerActionDemand",targetID: demand.id)
            try database.link(ownerKind: "providerActionDemand",ownerID: demand.id,targetKind: "providerActionBase",targetID: actionID)
            try insertProviderActionState(mapping.revising(state: "mapped"),expectedRevision: mapping.revision)
        }
    }
    private func insertNewDemand(_ value: RunDemand) throws {
        try safeID(value.id)
        guard value.revision == 1, value.state == "queued", value.executionIDs.isEmpty, value.resultID == nil, value.failure == nil, value.view == nil else { throw InvarError("INVALID_REQUEST","New demand must be queued without execution") }
        if let planID = value.planID { _ = try schedulingPlan(planID) }
        if let revision = value.changeRevisionID { _ = try loadChangeRevision(revision) }
        let rowID = Canonical.parts("invar.demand-revision/2",[value.id,"1"])
        let bytes = try Canonical.encode(value)
        try database.insert("demand",id: rowID,bytes: bytes)
        try database.advance("demand",id: value.id,expectedRevision: 0,recordID: rowID,state: value.state)
        if try database.load("principalIdentity",id: value.principal) != nil {
            try database.link(ownerKind: "demand",ownerID: value.id,targetKind: "principalIdentity",targetID: value.principal)
            try database.link(ownerKind: "demand",ownerID: rowID,targetKind: "principalIdentity",targetID: value.principal)
        }
        if let planID = value.planID {
            try database.link(ownerKind: "demand",ownerID: value.id,targetKind: "plan",targetID: planID)
            try database.link(ownerKind: "demand",ownerID: rowID,targetKind: "plan",targetID: planID)
        }
        if let revision = value.changeRevisionID { try database.link(ownerKind: "demand",ownerID: value.id,targetKind: "changeRevision",targetID: revision) }
    }
    public func loadDemand(_ id: String) throws -> RunDemand {
        try ensureAccepting()
        try safeID(id)
        guard let head = try database.head("demand",id: id) else { throw InvarError("REQUEST_NOT_FOUND","Unknown durable demand") }
        guard let bytes = try database.load("demand",id: head.recordID) else { throw InvarError("STORE_INTEGRITY","Demand head lost its retained revision") }
        let value = try JSONDecoder().decode(RunDemand.self,from: bytes)
        guard value.id == id, value.revision == head.revision, value.state == head.state else { throw InvarError("STORE_INTEGRITY","Demand head differs from immutable revision") }
        return value
    }
    public func beginDemandCancellation(_ id: String,principal: String,administrative: Bool) throws -> RunDemand {
        try ensureAccepting()
        return try transaction(usingFailureReserve: true) {
            let current = try loadDemand(id)
            guard administrative || current.principal == principal else { throw InvarError("POLICY_DENIED","A principal may cancel only its own operation",exitCode: 8) }
            guard ["queued","running"].contains(current.state) else { return current }
            let next = current.transitioning(to: "cancelling")
            try transitionDemand(next,expectedRevision: current.revision)
            return next
        }
    }
    public func finishDemandFailure(_ id: String,failure: InvarError,cancelled: Bool) throws -> RunDemand {
        try ensureAccepting()
        return try transaction(usingFailureReserve: true) {
            let current = try loadDemand(id)
            guard ["queued","running","cancelling"].contains(current.state) else { return current }
            let isCancelled = cancelled || current.state == "cancelling"
            let terminalFailure = isCancelled ? InvarError("CANCELLED","Cancelled operation completed owned cleanup",exitCode: 130) : failure
            let next = current.transitioning(to: isCancelled ? "cancelled" : "failed",failure: terminalFailure)
            try abortWatchRegistration(next)
            try transitionDemand(next,expectedRevision: current.revision)
            return next
        }
    }
    public func transitionDemand(_ value: RunDemand,expectedRevision: Int) throws {
        guard value.state != "completed" else { throw InvarError("INVALID_RESULT","Completed operations require the atomic result transaction") }
        try transitionDemand(value,expectedRevision: expectedRevision,allowCompletion: false)
    }
    func transitionDemand(_ value: RunDemand,expectedRevision: Int,allowCompletion: Bool) throws {
        try ensureAccepting()
        guard allowCompletion || value.state != "completed" else { throw InvarError("INVALID_RESULT","Unowned completion") }
        let failureTerminal = ["failed","cancelled","interrupted","notStarted","outcomeUnknown"].contains(value.state)
        try transaction(usingFailureReserve: failureTerminal) {
            let current = try loadDemand(value.id)
            guard current.revision == expectedRevision, value.revision == expectedRevision + 1, current.envelopeID == value.envelopeID, current.principal == value.principal, current.origin == value.origin, current.request == value.request, current.planID == value.planID, current.changeRevisionID == value.changeRevisionID, current.sourceRevision == value.sourceRevision,
                ["queued","running","cancelling"].contains(current.state), ["running","cancelling","completed","failed","cancelled","interrupted","notStarted","outcomeUnknown"].contains(value.state) else { throw InvarError("REVISION_CONFLICT","Invalid or competing demand transition") }
            let allowed: [String]
            switch current.state {
            case "queued": allowed = ["running","cancelling","failed","cancelled","interrupted","notStarted","outcomeUnknown"]
            case "running": allowed = ["running","completed","cancelling","failed","cancelled","interrupted","outcomeUnknown"]
            default: allowed = ["completed","cancelled","failed","interrupted","outcomeUnknown"]
            }
            guard value.state != current.state || Set(current.executionIDs).isStrictSubset(of: Set(value.executionIDs)),
                allowed.contains(value.state), Set(current.executionIDs).isSubset(of: Set(value.executionIDs)), Set(value.executionIDs).count == value.executionIDs.count,
                !failureTerminal || (value.failure != nil && value.resultID == nil) else { throw InvarError("INVALID_RESULT","Demand skipped start or lost execution/failure identity") }
            if let failure = value.failure { guard failure.message.utf8.count <= 4096, failure.code.utf8.count <= 128 else { throw InvarError("RESOURCE_LIMIT","Terminal failure exceeds reserved record size",exitCode: 6) } }
            if let reference = value.view {
                let actual = try loadView(reference.id), checked = try actual.reference()
                guard allowCompletion, value.state == "completed", checked == reference else { throw InvarError("INVALID_RESULT","Demand's committed view reference differs") }
            }
            if let result = value.resultID { guard value.state == "completed" else { throw InvarError("INVALID_RESULT","Noncompleted demand has a result") }; try safeID(result) }
            guard value.state != "completed" || value.resultID != nil && value.failure == nil else { throw InvarError("INVALID_RESULT","Completed operation lacks its retained result") }
            for id in value.executionIDs {
                let execution = try loadExecution(id)
                guard let planID = value.planID else { throw InvarError("INVALID_RESULT","Nonverification demand has execution interests") }
                let plan = try schedulingPlan(planID)
                guard let target = plan.jobs.first(where: { $0.id == execution.jobID }),
                    target.descriptorID == execution.descriptorID || target.executionKey != nil && target.executionKey == execution.inputKey else { throw InvarError("INPUT_MISMATCH","Demand interest differs from its complete scoped obligation") }
            }
            let rowID = Canonical.parts("invar.demand-revision/2",[value.id,String(value.revision)])
            let bytes = try Canonical.encode(value)
            try database.insert("demand",id: rowID,bytes: bytes)
            try database.advance("demand",id: value.id,expectedRevision: expectedRevision,recordID: rowID,state: value.state)
            for execution in value.executionIDs {
                try database.link(ownerKind: "demand",ownerID: value.id,targetKind: "execution",targetID: execution)
                try database.link(ownerKind: "demand",ownerID: rowID,targetKind: "execution",targetID: execution)
            }
            if let reference = value.view {
                try database.link(ownerKind: "demand",ownerID: rowID,targetKind: "view",targetID: reference.id)
            }
            if let result = value.resultID {
                let kind: String
                switch value.request { case .preparePlan: kind = "plan"; case .openChange: kind = "change"; case .sealChange: kind = "changeRevision"; case .verify: kind = "run"; case .reconcile: kind = "view"; case .watch: kind = "watch"; case .cancel: kind = "demand"; case .stopWatch: kind = "watch" }
                try database.link(ownerKind: "demand",ownerID: value.id,targetKind: kind,targetID: result)
                try database.link(ownerKind: "demand",ownerID: rowID,targetKind: kind,targetID: result)
            }
        }
    }
    public func loadReceipt(_ id: String) throws -> OperationReceipt? {
        try ensureAccepting()
        try safeID(id)
        guard let bytes = try database.load("operationReceipt",id: id) else { return nil }
        let value = try JSONDecoder().decode(OperationReceipt.self,from: bytes)
        guard value.id == id else { throw InvarError("STORE_INTEGRITY","Receipt identity differs") }; return value
    }
    public func pendingDemands() throws -> [RunDemand] {
        try ensureAccepting()
        let bytes = try database.current("demand",states: ["queued","running","cancelling"],limit: policy.maximumReservations,maximumBytes: 64 * 1024 * 1024)
        return try bytes.map { try JSONDecoder().decode(RunDemand.self,from: $0) }
    }
    public func pendingExecutions() throws -> [ExecutionRecord] {
        try ensureAccepting()
        let bytes = try database.current("execution",states: ["queued","running","cancelling"],limit: policy.maximumRecords,maximumBytes: 64 * 1024 * 1024)
        return try bytes.map { try JSONDecoder().decode(ExecutionRecord.self,from: $0) }
    }
    public func saveExecution(_ value: ExecutionRecord,expectedRevision: Int) throws {
        try ensureAccepting()
        try transaction(usingFailureReserve: ["failed","cancelled","interrupted"].contains(value.state)) {
            if expectedRevision == 0 {
                guard value.revision == 1, value.state == "queued", value.evidenceID == nil, value.failure == nil else { throw InvarError("INVALID_REQUEST","Invalid new execution") }
            } else {
                let current = try loadExecution(value.id)
                let allowed: [String]
                switch current.state {
                case "queued": allowed = ["running","failed","cancelled","interrupted"]
                case "running": allowed = ["cancelling","completed","failed","cancelled","interrupted"]
                case "cancelling": allowed = ["completed","failed","cancelled","interrupted"]
                default: allowed = []
                }
                guard allowed.contains(value.state), current.revision == expectedRevision, value.revision == expectedRevision + 1, current.inputKey == value.inputKey, current.descriptorID == value.descriptorID, current.jobID == value.jobID, current.planID == value.planID, ["queued","running","cancelling"].contains(current.state) else { throw InvarError("REVISION_CONFLICT","Execution changed or is terminal") }
            }
            if let id = value.descriptorID {
                let reference = try jobReference(id)
                guard reference.planID == value.planID, reference.id == value.jobID else { throw InvarError("INVALID_RESULT","Execution descriptor differs") }
            }
            guard ["queued","running","cancelling","completed","failed","cancelled","interrupted"].contains(value.state) else { throw InvarError("INVALID_RESULT","Unknown execution state") }
            guard value.state != "completed" || value.evidenceID != nil && value.failure == nil,
                !["failed","cancelled","interrupted"].contains(value.state) || value.failure != nil && value.evidenceID == nil else { throw InvarError("INVALID_RESULT","Execution terminal evidence/failure is inconsistent") }
            if let failure = value.failure { guard failure.message.utf8.count <= 4096, failure.code.utf8.count <= 128 else { throw InvarError("RESOURCE_LIMIT","Execution failure exceeds reserved record size",exitCode: 6) } }
            if let id = value.evidenceID { _ = try loadEvidence(id) }
            let rowID = Canonical.parts("invar.execution-revision/2",[value.id,String(value.revision)])
            let bytes = try Canonical.encode(value)
            try database.insert("execution",id: rowID,bytes: bytes)
            try database.advance("execution",id: value.id,expectedRevision: expectedRevision,recordID: rowID,state: value.state)
            try database.link(ownerKind: "execution",ownerID: value.id,targetKind: "plan",targetID: value.planID)
            try database.link(ownerKind: "execution",ownerID: rowID,targetKind: "plan",targetID: value.planID)
            if let id = value.descriptorID { try database.link(ownerKind: "execution",ownerID: value.id,targetKind: "descriptor",targetID: id); try database.link(ownerKind: "execution",ownerID: rowID,targetKind: "descriptor",targetID: id) }
            if ["failed","cancelled","interrupted"].contains(value.state) {
                for transfer in try transfers(value.id) {
                    try database.link(ownerKind: "execution",ownerID: value.id,targetKind: transfer.objectKind,targetID: transfer.objectID)
                    try database.link(ownerKind: "execution",ownerID: rowID,targetKind: transfer.objectKind,targetID: transfer.objectID)
                }
            }
            if let evidence = value.evidenceID {
                try database.link(ownerKind: "execution",ownerID: value.id,targetKind: "evidence",targetID: evidence)
                try database.link(ownerKind: "execution",ownerID: rowID,targetKind: "evidence",targetID: evidence)
            }
        }
    }
    public func loadExecution(_ id: String) throws -> ExecutionRecord {
        try ensureAccepting()
        try safeID(id)
        guard let head = try database.head("execution",id: id), let bytes = try database.load("execution",id: head.recordID) else { throw InvarError("EXECUTION_NOT_FOUND","Unknown execution") }
        let value = try JSONDecoder().decode(ExecutionRecord.self,from: bytes)
        guard value.id == id, value.revision == head.revision, value.state == head.state else { throw InvarError("STORE_INTEGRITY","Execution head differs") }; return value
    }
}
