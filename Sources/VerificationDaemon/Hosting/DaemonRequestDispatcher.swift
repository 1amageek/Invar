import ArchitectureCore
import Foundation
import VerificationCore
import VerificationFormal

public struct DaemonRequestDispatcher: DaemonRequestHandling {
    private let workspaceID: String
    private let epoch: String
    private let retentionSeconds: Double
    private let repository: any VerificationRepository
    private let coordinator: any WorkspaceCoordinating
    private let formal: (any FormalReadServing)?
    private let state: any DaemonStateReading
    public init(workspaceID: String,epoch: String,retentionSeconds: Double,repository: any VerificationRepository,coordinator: any WorkspaceCoordinating,state: any DaemonStateReading,formal: (any FormalReadServing)? = nil) {
        self.workspaceID = workspaceID; self.epoch = epoch; self.retentionSeconds = retentionSeconds
        self.formal = formal
        self.repository = repository; self.coordinator = coordinator; self.state = state
    }
    public func handle(_ request: JSONValue,channel: DaemonRPCChannel) async throws -> JSONValue? {
        guard case .object(let fields) = request, Set(fields.keys) == Set(["id","protocolVersion","workspaceID","method","body"]),
            request["protocolVersion"].int == 3, request["workspaceID"].string == workspaceID, let method = request["method"].string else { throw InvarError("PROTOCOL_MISMATCH","Unknown fields or workspace/protocol mismatch",exitCode: 2) }
        let body = request["body"]
        switch method {
        case "request.prepare":
            guard channel == .control else { throw InvarError("INVALID_REQUEST","Operation admission requires the control channel") }
            let proposed = try Self.decode(OperationPreparation.self,body)
            if case .reconcile = proposed.operation { throw InvarError("INVALID_REQUEST","Reassociation is an internal watch stage",exitCode: 2) }
            guard !proposed.key.isEmpty, proposed.key.utf8.count <= 128, !proposed.key.utf8.contains(0),
                proposed.timeout.isFinite, (1...3600).contains(proposed.timeout) else {
                throw InvarError("INVALID_REQUEST","Invalid request key or deadline",exitCode: 2)
            }
            let now = Date().timeIntervalSince1970
            let expiry = now + min(proposed.timeout,retentionSeconds)
            let fingerprint = try Canonical.identity(proposed.operation)
            let envelope = RequestEnvelope(id: UUID().uuidString,requestKey: proposed.key,principal: "local",
                workspaceID: workspaceID,fingerprint: fingerprint,operation: proposed.operation.name,
                daemonEpoch: epoch,expiresAt: expiry,retainUntil: now + retentionSeconds)
            return try JSONValue.encode(await repository.issueEnvelope(envelope,now: now))
        case "request.accept":
            guard channel == .control else { throw InvarError("INVALID_REQUEST","Operation admission requires the control channel") }
            let prepared = try Self.decode(PreparedOperation.self,body)
            guard prepared.envelope.principal == "local", prepared.envelope.workspaceID == workspaceID,
                prepared.envelope.daemonEpoch == epoch, prepared.envelope.watchID == nil else {
                throw InvarError("REQUEST_MISMATCH","Fixed request differs from this workspace or daemon epoch")
            }
            return try JSONValue.encode(await coordinator.submit(prepared.envelope,operation: prepared.operation))
        case "formal.query":
            guard channel == .data else { throw InvarError("INVALID_REQUEST","Formal queries use the data channel") }
            guard let formal else { throw InvarError("FORMAL_QUERY_UNSUPPORTED","This host has no configured formal read service",exitCode: 3) }
            let query = try Self.decode(FormalReadQuery.self,body)
            let result = try await formal.query(query,epoch: epoch)
            return try JSONValue.encode(result)
        case "query":
            let query = try Self.decode(WorkspaceQuery.self,body)
            return try await read(query,channel: channel)
        default: throw InvarError("METHOD_NOT_FOUND","Unknown daemon SDK method",exitCode: 2)
        }
    }
    private func read(_ query: WorkspaceQuery,channel: DaemonRPCChannel) async throws -> JSONValue {
        let control: Bool
        switch query { case .status,.receipt,.demand: control = true; default: control = false }
        guard control == (channel == .control) else { throw InvarError("INVALID_REQUEST","Query was sent on the wrong control/data channel",exitCode: 2) }
        switch query {
        case .status:
            let count = await coordinator.activeCount
            let watches = try await repository.watches(states: ["registering","active","paused","stopping"])
            let value = await state.status(activeOperations: count,watchCount: watches.count)
            return try JSONValue.encode(value)
        case .receipt(let id):
            guard let receipt = try await repository.loadReceipt(id) else { return .null }
            _ = try await coordinator.status(receipt.operationID,principal: "local",administrative: true)
            return try JSONValue.encode(receipt)
        case .demand(let id):
            let value = try await coordinator.status(id,principal: "local",administrative: true)
            return try JSONValue.encode(value)
        case .plan(let id):
            let plan = try await repository.schedulingPlan(id)
            guard plan.input.workspaceID == workspaceID else { throw InvarError("INPUT_MISMATCH","Plan belongs to another workspace") }
            return try JSONValue.encode(PlanSummary(plan))
        case .run(let id):
            let value = try await repository.loadRun(id)
            try await runAllowed(value)
            let summary = try VerificationRunSummary(value)
            return try JSONValue.encode(summary)
        case .runRecord(let id):
            let value = try await repository.loadRun(id)
            try await runAllowed(value)
            return try JSONValue.encode(value)
        case .evidenceSummary(let id):
            let value = try await repository.loadEvidence(id)
            try await evidenceAllowed(value)
            return try JSONValue.encode(EvidenceSummary(value,applicability: nil))
        case .replay(let id):
            let value = try await repository.loadReplay(id)
            return try JSONValue.encode(value)
        case .change(let id):
            let value = try await repository.loadChange(id)
            guard value.workspaceID == workspaceID else { throw InvarError("POLICY_DENIED","Change belongs to another workspace",exitCode: 8) }
            return try JSONValue.encode(value)
        case .changeRevision(let id):
            let value = try await repository.loadChangeRevision(id)
            guard value.before.workspaceID == workspaceID, value.after.workspaceID == workspaceID else { throw InvarError("POLICY_DENIED","Change revision belongs to another workspace",exitCode: 8) }
            return try JSONValue.encode(value)
        case .providerAction(let id):
            guard let base = try await repository.providerAction(id) else { return .null }
            guard base.input.workspaceID == workspaceID else { throw InvarError("POLICY_DENIED","Provider request belongs to another workspace") }
            let state = try await repository.providerActionState(id)
            let demand: RunDemand?
            if ["mapped","terminal"].contains(state.state), let job = state.jobID { demand = try await repository.loadDemand(job) } else { demand = nil }
            return try JSONValue.encode(ProviderActionSummary(state,demand: demand))
        case .publication(let id):
            guard let value = try await repository.loadPublication(id) else { return .null }
            guard value.input.workspaceID == workspaceID else { throw InvarError("POLICY_DENIED","Publication belongs to another workspace",exitCode: 8) }
            return try JSONValue.encode(PublicationSummary(value))
        case .watch(let id):
            let value = try await repository.loadWatch(id)
            guard value.workspaceID == workspaceID else { throw InvarError("POLICY_DENIED","Watch belongs to another workspace",exitCode: 8) }
            return try JSONValue.encode(value)
        case .watches:
            let values = try await repository.watches(states: ["registering","active","paused","stopping"])
            return try JSONValue.encode(values.filter { $0.workspaceID == workspaceID })
        case .sourceHead:
            let value = try await repository.sourceHead(workspaceID: workspaceID)
            return try JSONValue.encode(value)
        case .currentView:
            let value = try await repository.latestView(workspaceID: workspaceID)
            return try JSONValue.encode(value)
        case .view(let id):
            let value = try await repository.loadView(id)
            guard value.workspaceID == workspaceID else { throw InvarError("POLICY_DENIED","View belongs to another workspace",exitCode: 8) }
            return try JSONValue.encode(value)
        case .evidence(let id):
            let value = try await repository.loadEvidence(id)
            try await evidenceAllowed(value)
            return try JSONValue.encode(value)
        case .association(let id):
            let value = try await repository.loadAssociation(id)
            guard value.input.workspaceID == workspaceID else { throw InvarError("POLICY_DENIED","Association belongs to another workspace",exitCode: 8) }
            return try JSONValue.encode(value)
        }
    }
    private func runAllowed(_ run: VerificationRun) async throws {
        let plan = try await repository.schedulingPlan(run.planID)
        guard plan.input.workspaceID == workspaceID else { throw InvarError("POLICY_DENIED","Run belongs to another workspace",exitCode: 8) }
    }
    private func evidenceAllowed(_ evidence: VerificationEvidence) async throws {
        let input = try await repository.inputReference(evidence.inputID)
        guard input.workspaceID == workspaceID else { throw InvarError("POLICY_DENIED","Evidence belongs to another workspace",exitCode: 8) }
    }
    private static func decode<Value: Codable>(_ type: Value.Type,_ value: JSONValue) throws -> Value {
        let decoded = try value.decode(type)
        let encoded = try JSONValue.encode(decoded)
        guard encoded == value else { throw InvarError("INVALID_REQUEST","Unknown or noncanonical typed request fields",exitCode: 2) }
        return decoded
    }
}
