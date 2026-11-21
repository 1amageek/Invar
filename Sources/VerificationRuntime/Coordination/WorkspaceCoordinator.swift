import Foundation
import VerificationCore

public actor WorkspaceCoordinator: ExternalWorkspaceCoordinating {
    private let repository: any VerificationRepository
    private let scheduler: any VerificationScheduling
    private let authorization: any WorkspaceAuthorizationChecking
    private let operations: any WorkspaceOperationExecuting
    private let publisher: (any VerificationPublishing)?
    private let external: (any ExternalAdmissionAuthorizing)?
    private let epoch: String
    private let maximumDemands: Int
    private var tasks: [String:Task<Void,Never>] = [:]
    private var failures: [String:InvarError] = [:]
    private var accepting: [String:(RequestEnvelope,Task<OperationReceipt,any Error>)] = [:]
    private var admissionOpen: Bool
    private var stopped = false
    public init(repository: any VerificationRepository,scheduler: any VerificationScheduling,authorization: any WorkspaceAuthorizationChecking,operations: any WorkspaceOperationExecuting,epoch: String,maximumDemands: Int,acceptingRequests: Bool = true,publisher: (any VerificationPublishing)? = nil,external: (any ExternalAdmissionAuthorizing)? = nil) {
        self.external = external
        self.publisher = publisher
        self.repository = repository; self.scheduler = scheduler; self.authorization = authorization; self.operations = operations
        admissionOpen = acceptingRequests
        self.epoch = epoch; self.maximumDemands = maximumDemands
    }
    public func submitExternal(actionID: String) async throws -> OperationReceipt {
        guard admissionOpen, !stopped, failures.isEmpty, let external else { throw InvarError("COORDINATOR_STOPPED","External admission is closed") }
        let permit = try await external.takeStart(actionID)
        guard permit.actionID == actionID, let base = try await repository.providerAction(actionID) else { throw InvarError("ACTION_NOT_FOUND","External admission lacks its original preflight") }
        let envelope = base.envelope, operation = base.operation
        guard envelope.daemonEpoch == epoch, envelope.fingerprint == (try Canonical.identity(operation)), envelope.expiresAt > Date().timeIntervalSince1970 else { throw InvarError("REQUEST_EXPIRED","External authority is changed or expired") }
        let authority = try await authorization.authority(principal: envelope.principal,operation: operation,policyRevision: envelope.policyRevision,capabilityCeiling: Set(envelope.capabilities))
        guard authority.capabilities.contains(operation.requiredCapability), admissionOpen, !stopped,
            tasks.count + accepting.count < maximumDemands else { throw InvarError("RESOURCE_LIMIT","External authority or operation capacity is unavailable") }
        guard accepting[envelope.id] == nil else { throw InvarError("IDEMPOTENCY_CONFLICT","External acceptance is already active") }
        let task = Task { try await self.acceptExternal(permit,base: base) }
        accepting[envelope.id] = (envelope,task)
        defer { accepting.removeValue(forKey: envelope.id) }
        return try await task.value
    }
    private func acceptExternal(_ permit: ExternalAdmission,base: ProviderActionRegistration) async throws -> OperationReceipt {
        let planID: String?, changeID: String?, sourceRevision: Int
        switch base.operation {
        case .verify(let id,let change,_,_):
            let plan = try await repository.schedulingPlan(id)
            guard plan.input == base.input else { throw InvarError("INPUT_MISMATCH","External plan input differs") }
            let source = try await repository.sourceHead(workspaceID: base.input.workspaceID)
            sourceRevision = source?.daemonEpoch == epoch && source?.input.sourceIdentity == base.input.sourceIdentity ? source!.revision : 0
            planID = id; changeID = change
        case .cancel: planID = nil; changeID = nil; sourceRevision = 0
        default: throw InvarError("INVALID_REQUEST","Unsupported external operation")
        }
        let demand = RunDemand(id: permit.receipt.operationID,envelopeID: base.envelope.id,principal: base.envelope.principal,origin: "provider",request: base.operation,planID: planID,changeRevisionID: changeID,sourceRevision: sourceRevision,state: "queued",revision: 1,executionIDs: [],resultID: nil,failure: nil)
        try await repository.acceptExternalDemand(permit.receipt,demand: demand,actionID: base.id)
        if stopped {
            _ = try await repository.finishDemandFailure(demand.id,failure: InvarError("NOT_STARTED","Daemon stopped after external acceptance"),cancelled: false)
        } else { start(demand.id,envelope: base.envelope) }
        return permit.receipt
    }
    public func submitWatch(watchID: String,operation: WorkspaceOperation) async throws -> OperationReceipt {
        let envelope = try await repository.issueWatchEnvelope(watchID: watchID,operation: operation,epoch: epoch,now: Date().timeIntervalSince1970)
        return try await submit(envelope,operation: operation)
    }
    public func submit(_ envelope: RequestEnvelope,operation: WorkspaceOperation) async throws -> OperationReceipt {
        guard admissionOpen, !stopped, failures.isEmpty else { throw InvarError("COORDINATOR_STOPPED","Admission is stopped or recovery is required",exitCode: 6) }
        let fingerprint = try Canonical.identity(operation)
        guard envelope.daemonEpoch == epoch, envelope.operation == operation.name, envelope.fingerprint == fingerprint else { throw InvarError("REQUEST_MISMATCH","Typed request differs from fixed envelope") }
        if envelope.watchID != nil { try await repository.validateWatchRequest(envelope,operation: operation,now: Date().timeIntervalSince1970) }
        let authority = try await authorization.authority(principal: envelope.principal,operation: operation,policyRevision: envelope.policyRevision,capabilityCeiling: envelope.hasCapabilityCeiling ? Set(envelope.capabilities) : nil)
        guard authority.principal == envelope.principal, authority.policyRevision == envelope.policyRevision,
            !envelope.hasCapabilityCeiling || Set(envelope.capabilities).isSubset(of: authority.capabilities) && envelope.capabilities.contains(operation.requiredCapability) else { throw InvarError("POLICY_DENIED","Authority identity/revision differs",exitCode: 8) }
        if let pending = accepting[envelope.id] {
            guard pending.0 == envelope else { throw InvarError("REQUEST_MISMATCH","In-flight envelope was changed") }
            return try await pending.1.value
        }
        if let receipt = try await repository.loadReceipt(envelope.id) {
            let id = Canonical.parts("invar.operation/2",[envelope.id])
            guard receipt.operationID == id, receipt.fingerprint == fingerprint else { throw InvarError("IDEMPOTENCY_CONFLICT","Original receipt differs") }
            return receipt
        }
        // Recheck after the lookup suspension before reserving one logical request.
        if let pending = accepting[envelope.id] {
            guard pending.0 == envelope else { throw InvarError("REQUEST_MISMATCH","In-flight envelope was changed") }
            return try await pending.1.value
        }
        guard !stopped, maximumDemands > 0, tasks.count + accepting.count < maximumDemands else { throw InvarError("RESOURCE_LIMIT","Durable operation capacity exhausted",exitCode: 6) }
        let task = Task { try await self.accept(envelope,operation: operation) }
        accepting[envelope.id] = (envelope,task)
        defer { accepting.removeValue(forKey: envelope.id) }
        return try await task.value
    }
    private func accept(_ envelope: RequestEnvelope,operation: WorkspaceOperation) async throws -> OperationReceipt {
        let id = Canonical.parts("invar.operation/2",[envelope.id])
        let planID: String?, changeRevisionID: String?, sourceRevision: Int
        if case .verify(let plan,let change,let replay,_) = operation {
            let value = try await repository.schedulingPlan(plan)
            guard value.input.workspaceID == envelope.workspaceID else { throw InvarError("INPUT_MISMATCH","Plan belongs to another workspace") }
            if let node = operation.verificationNode {
                guard node.snapshotID == value.input.snapshotID else { throw InvarError("INPUT_MISMATCH","Selected snapshot differs from the verification plan") }
                let inventory = try await repository.inventory(value.input)
                guard inventory.entities.contains(where: { $0.id == node.entityID }) else { throw InvarError("INPUT_MISMATCH","Selected node is absent from the sealed snapshot") }
            }
            if let replay {
                let old = try await repository.loadRun(replay)
                guard old.planID == plan else { throw InvarError("INPUT_MISMATCH","Replay differs from its original plan") }
            }
            if let change {
                let revision = try await repository.loadChangeRevision(change)
                guard revision.after == value.input else { throw InvarError("INPUT_MISMATCH","Plan is not bound to the sealed change") }
            }
            let source = try await repository.sourceHead(workspaceID: envelope.workspaceID)
            sourceRevision = source?.input.sourceIdentity == value.input.sourceIdentity && source?.daemonEpoch == epoch ? source!.revision : 0
            planID = plan; changeRevisionID = change
        } else if case .reconcile(let plan,let runID) = operation {
            let value = try await repository.schedulingPlan(plan), run = try await repository.loadRun(runID)
            let original = try await repository.schedulingPlan(run.planID)
            _ = try EvidenceReconciliation.associations(run: run,original: original,target: value)
            guard value.input.workspaceID == envelope.workspaceID else { throw InvarError("INPUT_MISMATCH","Reassociation targets another workspace") }
            let source = try await repository.sourceHead(workspaceID: envelope.workspaceID)
            guard let source, source.confirmed, source.input.sourceIdentity == value.input.sourceIdentity, source.daemonEpoch == epoch else { throw InvarError("INPUT_CHANGED","Reassociation requires the confirmed current target capture") }
            sourceRevision = source.revision
            planID = plan; changeRevisionID = nil
        } else {
            planID = nil; changeRevisionID = nil; sourceRevision = 0
        }
        let demand = RunDemand(id: id,envelopeID: envelope.id,principal: envelope.principal,origin: envelope.watchID == nil ? "internal" : "watch",request: operation,planID: planID,changeRevisionID: changeRevisionID,sourceRevision: sourceRevision,state: "queued",revision: 1,executionIDs: [],resultID: nil,failure: nil)
        let receipt = try await repository.acceptDemand(envelope,demand: demand,now: Date().timeIntervalSince1970)
        guard !stopped else {
            let current = try await repository.loadDemand(id)
            if current.state == "queued" { try await repository.transitionDemand(current.transitioning(to: "notStarted",failure: InvarError("NOT_STARTED","Daemon stopped before admission",exitCode: 6)),expectedRevision: current.revision) }
            return receipt
        }
        start(id,envelope: envelope)
        return receipt
    }
    private func start(_ id: String,envelope: RequestEnvelope) {
        guard tasks[id] == nil else { return }
        tasks[id] = Task {
            do {
                let remaining = envelope.expiresAt - Date().timeIntervalSince1970
                guard remaining > 0 else { throw InvarError("REQUEST_EXPIRED","Original operation deadline expired",exitCode: 6) }
                try await BoundedOperation.run(seconds: remaining) { try await self.perform(id,envelope: envelope) }
            } catch {
                do { try await self.recordFailure(id,error: error) }
                catch { self.failures[id] = InvarError("PERSISTENCE_FAILED","Terminal operation state could not be committed: \(error)",exitCode: 7) }
            }
            self.tasks.removeValue(forKey: id)
        }
    }
    private func perform(_ id: String,envelope: RequestEnvelope) async throws {
        try Task.checkCancellation()
        let queued = try await repository.loadDemand(id)
        guard queued.state == "queued" else { return }
        if envelope.watchID != nil { try await repository.validateWatchRequest(envelope,operation: queued.request,now: Date().timeIntervalSince1970) }
        let original = try await authorization.authority(principal: queued.principal,operation: queued.request,policyRevision: envelope.policyRevision,capabilityCeiling: envelope.hasCapabilityCeiling ? Set(envelope.capabilities) : nil)
        let capabilities = envelope.hasCapabilityCeiling ? original.capabilities.intersection(Set(envelope.capabilities)) : original.capabilities
        guard capabilities.contains(queued.request.requiredCapability) else { throw InvarError("POLICY_DENIED","Fixed request lacks its original scoped authority",exitCode: 8) }
        let authority = OperationAuthority(principal: original.principal,policyRevision: original.policyRevision,capabilities: capabilities)
        try Task.checkCancellation()
        let running = queued.transitioning(to: "running")
        try await repository.transitionDemand(running,expectedRevision: queued.revision)
        if case .verify(let planID,_,let replay,_) = running.request {
            let plan = try await repository.schedulingPlan(planID)
            try await publisher?.reserve(demand: running,plan: plan)
            let run = try await scheduler.run(plan.id,nativeExecutionAllowed: authority.capabilities.contains(.nativeExecution),replay: replay != nil || (running.origin == "provider" && running.request.verificationNode != nil),persist: false,demandID: running.id)
            try Task.checkCancellation()
            try await completeRun(running,run: run,plan: plan)
        } else if case .reconcile(let planID,let runID) = running.request {
            let plan = try await repository.schedulingPlan(planID)
            try await publisher?.reserve(demand: running,plan: plan)
            let run = try await repository.loadRun(runID), original = try await repository.schedulingPlan(run.planID)
            let associations = try EvidenceReconciliation.associations(run: run,original: original,target: plan)
            try await completeReassociation(running,run: run,plan: plan,associations: associations)
        } else {
            let result: String
            if case .cancel(let target) = running.request {
                guard target != running.id else { throw InvarError("INVALID_REQUEST","An operation cannot await its own cancellation") }
                try await cancel(target,principal: authority.principal,administrative: authority.capabilities.contains(.administration)); result = target
            } else { result = try await operations.execute(running,authority: authority) }
            try Task.checkCancellation()
            let current = try await repository.loadDemand(id)
            try await repository.completeDemand(current.transitioning(to: "completed",resultID: result),run: nil,view: nil,expectedRevision: current.revision)
        }
    }
    private func completeRun(_ demand: RunDemand,run: VerificationRun,plan: SchedulingPlan) async throws {
        var associations: [EvidenceAssociation] = []
        for value in run.associations {
            guard let evidence = run.attempts.first(where: { $0.id == value.evidenceID }) else { throw InvarError("INVALID_RESULT","Run association lacks evidence") }
            associations.append(EvidenceAssociation.make(evidence: evidence,targetDescriptorID: value.targetDescriptorID,changeRevisionID: value.input.id == plan.input.id ? demand.changeRevisionID : nil,input: value.input,status: value.applicability,basis: value.basis,unknownBoundaries: value.unknownBoundaries,reuseDecision: value.reuseDecision))
        }
        let bound = VerificationRun(id: run.id,planID: run.planID,attempts: run.attempts,associations: associations,accepted: run.accepted,diagnostics: run.diagnostics)
        let change: ChangeRevision?
        if let id = demand.changeRevisionID { change = try await repository.loadChangeRevision(id) } else { change = nil }
        for _ in 0..<maximumDemands {
            try Task.checkCancellation()
            let current = try await repository.loadDemand(demand.id)
            let sequence = try await repository.nextViewSequence(workspaceID: plan.input.workspaceID)
            let target = associations.first?.input ?? plan.input
            guard associations.allSatisfy({ $0.input == target }) else { throw InvarError("INVALID_RESULT","Run mixed current-input associations") }
            let sameInput = target == plan.input
            let view = ChangeVerificationView(workspaceID: target.workspaceID,changeRevisionID: sameInput ? demand.changeRevisionID : nil,input: target,daemonEpoch: epoch,sourceRevision: demand.sourceRevision,sequence: sequence,delta: sameInput ? change?.delta : nil,impactEntityIDs: sameInput ? change?.impactEntityIDs ?? [] : [],unknownBoundaries: sameInput ? change?.diagnostics ?? [] : ["Current input differs from sealed change/plan"],planIDs: [plan.id],runIDs: [bound.id],evidenceIDs: bound.attempts.map(\.id),associations: bound.associations,pendingDemandIDs: [],diagnostics: bound.diagnostics)
            let terminal = current.transitioning(to: "completed",resultID: bound.id,executionIDs: Array(Set(current.executionIDs + bound.attempts.compactMap(\.executionID))).sorted())
            let publication = try await publisher?.prepare(demand: current,run: bound,view: view)
            do { try await repository.completeDemand(terminal,run: bound,view: view,publication: publication,expectedRevision: current.revision); return }
            catch let error as InvarError where error.code == "REVISION_CONFLICT" { continue }
        }
        throw InvarError("RESOURCE_CONTENTION","Common view changed throughout bounded terminal commit retries",exitCode: 6)
    }
    private func completeReassociation(_ demand: RunDemand,run: VerificationRun,plan: SchedulingPlan,associations: [EvidenceAssociation]) async throws {
        for _ in 0..<maximumDemands {
            try Task.checkCancellation()
            let current = try await repository.loadDemand(demand.id)
            let sequence = try await repository.nextViewSequence(workspaceID: plan.input.workspaceID)
            let unknown = Array(Set(associations.flatMap(\.unknownBoundaries))).sorted()
            let view = ChangeVerificationView(workspaceID: plan.input.workspaceID,changeRevisionID: nil,input: plan.input,daemonEpoch: epoch,sourceRevision: demand.sourceRevision,sequence: sequence,delta: nil,impactEntityIDs: [],unknownBoundaries: unknown,planIDs: [plan.id],runIDs: [run.id],evidenceIDs: run.attempts.map(\.id),associations: associations,pendingDemandIDs: [],diagnostics: ["Original completed evidence reassociated to identical captured scope; no new backend execution"])
            let reference = try view.reference(), publication = try await publisher?.prepare(demand: current,run: run,view: view)
            let terminal = current.transitioning(to: "completed",resultID: reference.id)
            do { try await repository.completeDemand(terminal,run: nil,view: view,publication: publication,expectedRevision: current.revision); return }
            catch let error as InvarError where error.code == "REVISION_CONFLICT" { continue }
        }
        throw InvarError("RESOURCE_CONTENTION","Reassociation view changed throughout bounded commit retries",exitCode: 6)
    }
    private func recordFailure(_ id: String,error: any Error) async throws {
        let typed = error as? InvarError ?? InvarError(error is CancellationError ? "CANCELLED" : "OPERATION_FAILED",String(describing: error),exitCode: error is CancellationError ? 130 : 7)
        let bounded = InvarError(typed.code,String(typed.message.prefix(1024)),exitCode: typed.exitCode)
        let terminal = try await repository.finishDemandFailure(id,failure: bounded,cancelled: error is CancellationError)
        if terminal.state != "completed" { try await publisher?.abandon(demandID: id,failure: terminal.failure ?? bounded) }
    }
    public func cancel(_ id: String,principal: String,administrative: Bool = false) async throws {
        let current = try await repository.beginDemandCancellation(id,principal: principal,administrative: administrative)
        guard current.state == "cancelling" else { return }
        if let task = tasks[id] { task.cancel(); await task.value }
        try await recordFailure(id,error: CancellationError())
    }
    public func recover() async throws {
        guard tasks.isEmpty else { throw InvarError("RECOVERY_BLOCKED","Cannot recover with active operation tasks") }
        let pending = try await repository.pendingDemands()
        guard maximumDemands > 0, pending.count <= maximumDemands else { throw InvarError("RECOVERY_BLOCKED","Accepted operation inventory exceeds configured recovery capacity",exitCode: 6) }
        for demand in pending {
            if stopped {
                let terminal = demand.transitioning(to: demand.state == "queued" ? "notStarted" : "interrupted",failure: InvarError("NOT_STARTED","Stop prevented recovery from starting prior work",exitCode: 6))
                try await repository.completeDemand(terminal,run: nil,view: nil,expectedRevision: demand.revision)
                continue
            }
            if ["internal","watch"].contains(demand.origin), demand.state == "queued" {
                do {
                    let envelope = try await repository.loadEnvelope(demand.envelopeID)
                    let receipt = try await repository.loadReceipt(envelope.id)
                    let fingerprint = try Canonical.identity(demand.request)
                    guard receipt?.operationID == demand.id, receipt?.fingerprint == fingerprint, envelope.fingerprint == fingerprint, envelope.expiresAt > Date().timeIntervalSince1970 else { throw InvarError("REQUEST_EXPIRED","Original accepted request/deadline cannot be renewed by recovery",exitCode: 6) }
                    if envelope.watchID != nil { try await repository.validateWatchRequest(envelope,operation: demand.request,now: Date().timeIntervalSince1970) }
                    _ = try await authorization.authority(principal: demand.principal,operation: demand.request,policyRevision: envelope.policyRevision,capabilityCeiling: envelope.hasCapabilityCeiling ? Set(envelope.capabilities) : nil)
                    start(demand.id,envelope: envelope)
                } catch { try await recordFailure(demand.id,error: error) }
            } else {
                let state = demand.state == "queued" ? "notStarted" : "interrupted"
                let terminal = demand.transitioning(to: state,failure: InvarError("INTERRUPTED","Prior operation is retained without permission to restart execution",exitCode: 6))
                try await repository.completeDemand(terminal,run: nil,view: nil,expectedRevision: demand.revision)
            }
        }
    }
    public func status(_ id: String,principal: String,administrative: Bool = false) async throws -> RunDemand {
        if let failure = failures[id] { throw failure }
        let value = try await repository.loadDemand(id)
        guard administrative || value.principal == principal else { throw InvarError("POLICY_DENIED","Operation belongs to another principal",exitCode: 8) }
        return value
    }
    public var activeCount: Int { tasks.count + accepting.count }
    public func openAdmission() throws {
        guard !stopped, failures.isEmpty else { throw InvarError("COORDINATOR_STOPPED","Stopped/recovery-blocked admission cannot reopen") }
        admissionOpen = true
    }
    public func closeAdmission() { admissionOpen = false; stopped = true }
    public func shutdown() async throws {
        stopped = true
        let admissions = accepting.values.map { $0.1 }
        for admission in admissions { _ = await admission.result }
        let active = Array(tasks.values)
        for task in active { task.cancel() }
        for task in active { await task.value }
        await scheduler.shutdown()
        guard failures.isEmpty else { throw InvarError("RECOVERY_BLOCKED","Operation persistence failed during shutdown",exitCode: 7) }
    }
}
