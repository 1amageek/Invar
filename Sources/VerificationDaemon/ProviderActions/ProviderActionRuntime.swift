import ArchitectureClient
import ArchitectureCore
import ArchitectureExtensions
import Foundation
import VerificationCore
import VerificationExplorer
import VerificationRuntime

/// Consumes only a concrete live SDK start decision, with durable Invar mapping before work.
actor ProviderActionRuntime: ExternalAdmissionAuthorizing {
    private let operations: WorkspaceOperations
    private let connection: ExplorerProviderConnection
    private let repository: any VerificationRepository
    private let coordinator: any ExternalWorkspaceCoordinating
    private let resources: any WorkspaceResourceAdmitting
    private let epoch: String
    private let retentionSeconds: Double
    private var deliveries: [String:Task<Void,Never>] = [:]
    private var permits: [String:ExternalAdmission] = [:]
    private var pump: Task<Void,Never>?
    private var closed = false
    private var failure: InvarError?
    init(operations: WorkspaceOperations,connection: ExplorerProviderConnection,repository: any VerificationRepository,coordinator: any ExternalWorkspaceCoordinating,resources: any WorkspaceResourceAdmitting,epoch: String,retentionSeconds: Double) {
        self.operations = operations
        self.connection = connection; self.repository = repository; self.coordinator = coordinator; self.resources = resources; self.epoch = epoch; self.retentionSeconds = retentionSeconds
    }
    func start() throws {
        guard pump == nil, !closed else { throw InvarError("INVALID_TRANSITION","Provider Action runtime is already started or closed") }
        pump = Task {
            var reconciledSession: String?, nextReconcile = ContinuousClock.now
            while !Task.isCancelled, !self.closed {
                self.failure = nil
                do {
                    let provider = try await self.connection.provider()
                    if reconciledSession != provider.registration.sessionID || ContinuousClock.now >= nextReconcile {
                        try await self.reconcile(provider)
                        reconciledSession = provider.registration.sessionID
                        nextReconcile = ContinuousClock.now.advanced(by: .seconds(3))
                    }
                    try await self.progress(provider)
                    if let intent = try await provider.nextAction() { try await self.deliver(intent,provider: provider) }
                } catch is CancellationError { return }
                catch { self.failure = Self.error(error) }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }
    func diagnostic() -> InvarError? { failure }
    static func error(_ error: any Error) -> InvarError {
        if let value = error as? InvarError { return InvarError(String(value.code.prefix(128)),String(value.message.prefix(512)),exitCode: value.exitCode) }
        if let value = error as? ArchitectureError { return InvarError(String(value.code.prefix(128)),String(value.message.prefix(512)),exitCode: value.exitCode) }
        if error is CancellationError { return InvarError("CANCELLED","Provider delivery stopped before first-start completion",exitCode: 6) }
        return InvarError("ACTION_DELIVERY_FAILED",String(String(describing: error).prefix(512)),exitCode: 7)
    }
    private func sourceBinding(_ input: VerificationInput,entityIDs: [String]) async throws -> ExtensionBinding {
        let inventory = try await repository.inventory(input)
        guard let originals = inventory.originalRecords["inputManifest"], originals.count == 1 else { throw InvarError("INPUT_MISMATCH","Original source manifest is unavailable") }
        let original = try JSONDecoder().decode(InputManifest.self,from: originals[0])
        let digest = try original.digest
        guard original.workspaceID == input.workspaceID, original.snapshotID == input.snapshotID else { throw InvarError("INPUT_MISMATCH","Original source manifest differs") }
        return ExtensionBinding(workspaceID: input.workspaceID,snapshotID: input.snapshotID,inputManifestDigest: digest,entityIDs: entityIDs)
    }
    private func preflight(_ intent: ActionIntent,provider: ExtensionProviderClient) async throws -> ProviderActionRegistration {
        guard !closed, permits.count < 32, intent.deadline > Date().timeIntervalSince1970,
            intent.binding.factIDs.isEmpty else { throw InvarError("POLICY_DENIED","Action is expired, scoped differently or admission is closed") }
        let operation: WorkspaceOperation, input: VerificationInput, originalRun: ExtensionRun?, runRequestID: String
        switch intent.actionID {
        case "verify-project":
            guard intent.binding.entityIDs.count == 1, let selected = intent.binding.entityIDs.first, let path = intent.arguments["configuration"].string else { throw InvarError("INVALID_REQUEST","Project verification requires one subject and configuration") }
            let planID = try await operations.prepareProject(binding: intent.binding,configurationPath: path)
            let plan = try await repository.schedulingPlan(planID)
            input = plan.input
            operation = .verify(planID: planID,changeRevisionID: nil,replayOfRunID: nil,node: VerificationNode(snapshotID: input.snapshotID,entityID: selected))
            originalRun = nil; runRequestID = intent.requestID
        case "verify-model":
            guard intent.binding.entityIDs.count == 1, let selected = intent.binding.entityIDs.first else {
                throw InvarError("INVALID_REQUEST","Model verification requires one selected source node")
            }
            let planID = try await operations.prepareModel(binding: intent.binding,specification: intent.arguments["specification"].string)
            let plan = try await repository.schedulingPlan(planID)
            input = plan.input
            operation = .verify(planID: planID,changeRevisionID: nil,replayOfRunID: nil,node: VerificationNode(snapshotID: input.snapshotID,entityID: selected))
            originalRun = nil; runRequestID = intent.requestID
        case "verify":
            guard intent.binding.entityIDs.isEmpty, let id = intent.arguments["planID"].string else { throw InvarError("INVALID_REQUEST","Verification requires a sealed plan") }
            let plan = try await repository.schedulingPlan(id)
            input = plan.input; operation = .verify(planID: id,changeRevisionID: intent.arguments["changeRevisionID"].string,replayOfRunID: nil)
            originalRun = nil; runRequestID = intent.requestID
        case "cancel":
            guard let id = intent.arguments["requestID"].string, let parent = try await repository.providerAction(id) else { throw InvarError("ACTION_NOT_FOUND","Cancellation requires an original Provider request") }
            let mapping = try await repository.providerActionState(id)
            guard mapping.state == "mapped", let job = mapping.jobID, intent.arguments["jobID"].string == job else { throw InvarError("POLICY_DENIED","Cancellation differs from the original accepted job") }
            let run = try JSONDecoder().decode(ExtensionRun.self,from: parent.run)
            guard intent.arguments["runID"].string == run.id else { throw InvarError("POLICY_DENIED","Cancellation differs from original source run") }
            input = parent.input; operation = .cancel(demandID: job); originalRun = run; runRequestID = parent.runRequestID
        default: throw InvarError("INVALID_REQUEST","Unknown Provider operation")
        }
        let binding: ExtensionBinding
        if let originalRun { binding = originalRun.binding } else { binding = try await sourceBinding(input,entityIDs: operation.verificationNode.map { [$0.entityID] } ?? []) }
        guard binding == intent.binding else { throw InvarError("INPUT_MISMATCH","Action differs from original sealed source scope") }
        let now = Date().timeIntervalSince1970
        let expiry = min(intent.deadline, now + retentionSeconds)
        let fingerprint = try Canonical.identity(operation)
        let envelope = RequestEnvelope(id: UUID().uuidString,requestKey: "explorer:" + intent.requestID,principal: "local",
            workspaceID: input.workspaceID,fingerprint: fingerprint,operation: operation.name,
            daemonEpoch: epoch,expiresAt: expiry,retainUntil: now + retentionSeconds)
        let fixed = try await repository.issueEnvelope(envelope,now: now)
        let run: ExtensionRun
        if let originalRun { try await provider.requireOriginalRun(originalRun); run = originalRun }
        else { run = try await provider.begin(runID: runRequestID,scope: intent.binding.entityIDs.first ?? "workspace",contributionSetID: "verification",binding: intent.binding,kinds: intent.binding.entityIDs.isEmpty ? ["graph"] : ["annotation","graph"],viewIDs: []) }
        guard run.binding == intent.binding, run.providerID == provider.registration.providerID,
            originalRun != nil || !run.committed && run.completion == "pending" else { throw InvarError("INVALID_PUBLICATION","Provider preflight run is inconsistent") }
        let rawIntent = try CanonicalJSON.encode(intent), rawRun = try CanonicalJSON.encode(run)
        let value = ProviderActionRegistration(id: intent.requestID,envelope: fixed,operation: operation,input: input,sourceFingerprint: intent.requestFingerprint,intent: rawIntent,runRequestID: runRequestID,run: rawRun,expiresAt: intent.deadline+3600)
        try await repository.createProviderAction(value)
        return value
    }
    private func deliver(_ intent: ActionIntent,provider: ExtensionProviderClient) async throws {
        guard deliveries[intent.requestID] == nil else { return }
        guard !closed, deliveries.count < 32 else {
            try await provider.receipt(for: intent,receipt: ActionReceipt(rejected: "RESOURCE_LIMIT: Provider delivery capacity exhausted"))
            return
        }
        deliveries[intent.requestID] = Task {
            do { try await BoundedOperation.run(seconds: intent.deadline - Date().timeIntervalSince1970) { try await self.receive(intent,provider: provider) } }
            catch { self.failure = Self.error(error) }
            self.deliveries.removeValue(forKey: intent.requestID)
        }
    }
    private func receive(_ intent: ActionIntent,provider: ExtensionProviderClient) async throws {
        let resourceID = "provider-action-" + intent.requestID
        let workerAdmission = ["verify","verify-project"].contains(intent.actionID)
        if workerAdmission { try await resources.acquire(ResourceRequest(id: resourceID,memoryMiB: 256,processes: 0,scratchBytes: 0,priority: 0)) }
        defer { if workerAdmission { await resources.release(resourceID) } }
        if try await repository.providerAction(intent.requestID) != nil { try await reconcileIntent(intent,provider: provider); return }
        let base: ProviderActionRegistration
        do { base = try await preflight(intent,provider: provider) }
        catch {
            let failure = Self.error(error)
            try await provider.receipt(for: intent,receipt: ActionReceipt(rejected: failure.code + ": " + failure.message))
            throw failure
        }
        do {
            let reservation = try await connection.actionLedger.reserve(intent,providerID: provider.registration.providerID)
            guard let job = reservation.receipt.jobID else { throw InvarError("INVALID_RESULT","Concrete ledger accepted receipt has no job identity") }
            let old = try await repository.providerActionState(base.id)
            try await repository.saveProviderActionState(old.revising(state: reservation.mayStart ? "accepted" : "outcomeUnknown",jobID: job),expectedRevision: old.revision)
            try await provider.receipt(for: intent,receipt: reservation.receipt)
            let run = try JSONDecoder().decode(ExtensionRun.self,from: base.run)
            try await provider.report(requestID: intent.requestID,jobID: job,runID: run.id,revision: 1,state: "unknown")
            guard reservation.mayStart, !closed else { return }
            let accepted = try await repository.providerActionState(base.id)
            try await repository.saveProviderActionState(accepted.revising(state: "accepted",reportedRevision: 1),expectedRevision: accepted.revision)
            let receipt = OperationReceipt(id: base.envelope.id,operationID: job,fingerprint: base.envelope.fingerprint,acceptedAt: Date().timeIntervalSince1970,daemonEpoch: epoch)
            permits[base.id] = ExternalAdmission(actionID: base.id,receipt: receipt)
            defer { permits.removeValue(forKey: base.id) }
            _ = try await coordinator.submitExternal(actionID: base.id)
        } catch {
            let failure = Self.error(error)
            let state = try await repository.providerActionState(base.id)
            if ["preflight","accepted"].contains(state.state) {
                try await repository.saveProviderActionState(state.revising(state: "outcomeUnknown",failure: failure),expectedRevision: state.revision)
            }
            throw failure
        }
    }
    func takeStart(_ actionID: String) async throws -> ExternalAdmission {
        guard !closed, let permit = permits.removeValue(forKey: actionID), let base = try await repository.providerAction(actionID),
            base.envelope.expiresAt > Date().timeIntervalSince1970 else { throw InvarError("ACTION_OUTCOME_UNKNOWN","No live first-start permission exists; retained receipt cannot restart work") }
        let provider = try await connection.provider(), intent = try JSONDecoder().decode(ActionIntent.self,from: base.intent)
        let receipt = try await connection.actionLedger.lookup(intent,providerID: provider.registration.providerID)
        guard receipt.jobID == permit.receipt.operationID else { throw InvarError("IDEMPOTENCY_CONFLICT","SDK receipt changed before admission") }
        // Idempotent receipt acknowledgement rechecks the current source permission before Core admission.
        try await provider.receipt(for: intent,receipt: receipt)
        try Task.checkCancellation()
        guard !closed else { throw InvarError("COORDINATOR_STOPPED","Provider admission closed during authorization") }
        return permit
    }
    private func reconcileIntent(_ intent: ActionIntent,provider: ExtensionProviderClient) async throws {
        let receipt = try await connection.actionLedger.lookup(intent,providerID: provider.registration.providerID)
        try await provider.receipt(for: intent,receipt: receipt)
        guard let base = try await repository.providerAction(intent.requestID) else { throw InvarError("ACTION_OUTCOME_UNKNOWN","SDK accepted receipt has no Invar preflight; no work can be restarted") }
        guard base.sourceFingerprint == intent.requestFingerprint, let job = receipt.jobID else { throw InvarError("IDEMPOTENCY_CONFLICT","Original Action receipt/preflight differs") }
        let old = try await repository.providerActionState(base.id)
        if ["preflight","accepted"].contains(old.state) {
            try await repository.saveProviderActionState(old.revising(state: "outcomeUnknown",jobID: job,failure: InvarError("ACTION_OUTCOME_UNKNOWN","Prior SDK acceptance lacks runnable mapping; first-start permission does not survive reconciliation")),expectedRevision: old.revision)
        } else if let original = old.jobID, original != job { throw InvarError("IDEMPOTENCY_CONFLICT","Original Core mapping differs from SDK receipt") }
    }
    private func reconcile(_ provider: ExtensionProviderClient) async throws {
        let dispatches = try await provider.reconcile()
        guard dispatches.array.count <= 512, try CanonicalJSON.encode(dispatches).count <= 4 * 1024 * 1024 else { throw InvarError("RESOURCE_LIMIT","Action reconciliation exceeds bounded profile") }
        for dispatch in dispatches.array {
            try Task.checkCancellation()
            let intent = try dispatch["intent"].decode(ActionIntent.self)
            if deliveries[intent.requestID] != nil { continue }
            do { try await reconcileIntent(intent,provider: provider) }
            catch { failure = Self.error(error) }
        }
    }
    private func progress(_ provider: ExtensionProviderClient) async throws {
        for id in try await repository.providerActionIDs() {
            try Task.checkCancellation()
            let state = try await repository.providerActionState(id)
            guard ["mapped","outcomeUnknown"].contains(state.state), let job = state.jobID,
                let base = try await repository.providerAction(id), base.expiresAt > Date().timeIntervalSince1970 else { continue }
            let run = try JSONDecoder().decode(ExtensionRun.self,from: base.run)
            if state.state == "outcomeUnknown" {
                guard state.reportedRevision == 0 else { continue }
                try await provider.report(requestID: id,jobID: job,runID: run.id,revision: 1,state: "unknown")
                try await repository.saveProviderActionState(state.revising(state: "outcomeUnknown",reportedRevision: 1),expectedRevision: state.revision)
                continue
            }
            let demand = try await repository.loadDemand(job), revision = demand.revision+1
            guard revision > state.reportedRevision else { continue }
            let status: String
            switch demand.state {
            case "queued","outcomeUnknown": status = "unknown"
            case "running","cancelling": status = "running"
            case "completed": status = "completed"
            case "cancelled": status = "cancelled"
            default: status = "failed"
            }
            try await provider.report(requestID: id,jobID: job,runID: run.id,revision: revision,state: status)
            let terminal = ["completed","failed","cancelled"].contains(status)
            try await repository.saveProviderActionState(state.revising(state: terminal ? "terminal" : "mapped",reportedRevision: revision),expectedRevision: state.revision)
        }
    }
    func closeAdmission() async {
        closed = true; pump?.cancel(); await pump?.value; pump = nil
        let active = Array(deliveries.values)
        for task in active { task.cancel() }
        for task in active { await task.value }
        permits.removeAll()
    }
}
