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
    private let authentication: any DaemonAuthenticating
    private let formal: (any FormalReadServing)?
    private let state: any DaemonStateReading
    public init(workspaceID: String,epoch: String,retentionSeconds: Double,repository: any VerificationRepository,coordinator: any WorkspaceCoordinating,authentication: any DaemonAuthenticating,state: any DaemonStateReading,formal: (any FormalReadServing)? = nil) {
        self.workspaceID = workspaceID; self.epoch = epoch; self.retentionSeconds = retentionSeconds
        self.formal = formal
        self.repository = repository; self.coordinator = coordinator; self.authentication = authentication; self.state = state
    }
    public func handle(_ request: JSONValue,peer: ConnectionPeer,channel: DaemonRPCChannel) async throws -> JSONValue? {
        guard case .object(let fields) = request, Set(fields.keys) == Set(["id","protocolVersion","workspaceID","method","epoch","credential","body"]),
            request["protocolVersion"].int == 2, request["workspaceID"].string == workspaceID, let method = request["method"].string else { throw InvarError("PROTOCOL_MISMATCH","Unknown fields or workspace/protocol mismatch",exitCode: 2) }
        let body = request["body"]
        if method == "session.open" {
            guard channel == .control, request["credential"] == .null, request["epoch"] == .null,
                case .object(let values) = body, Set(values.keys) == Set(["label","capabilities","resumeCredential"]), body["label"] == .null || body["label"].string != nil,
                body["resumeCredential"] == .null || body["resumeCredential"].string != nil else { throw InvarError("INVALID_REQUEST","Invalid session-opening request",exitCode: 2) }
            let desired = try Self.decode([WorkspaceCapability].self,body["capabilities"])
            guard Set(desired).count == desired.count else { throw InvarError("INVALID_REQUEST","Duplicate capability request",exitCode: 2) }
            let grant = try await authentication.open(peer: peer,label: body["label"].string,requested: Set(desired),resumeCredential: body["resumeCredential"].string)
            return try JSONValue.encode(grant)
        }
        guard let credential = request["credential"].string, request["epoch"].string == epoch else { throw InvarError("AUTHENTICATION_REQUIRED","Missing or old-epoch session credential",exitCode: 8) }
        let authenticated = try await authentication.authenticate(credential: credential,epoch: epoch,peer: peer)
        let authority = authenticated.authority
        switch method {
        case "request.prepare":
            guard channel == .control else { throw InvarError("INVALID_REQUEST","Operation admission requires the control channel") }
            let proposed = try Self.decode(OperationPreparation.self,body)
            if case .reconcile = proposed.operation { throw InvarError("POLICY_DENIED","Reassociation is an internal fixed watch stage",exitCode: 8) }
            guard !proposed.key.isEmpty, proposed.key.utf8.count <= 128, !proposed.key.utf8.contains(0), proposed.timeout.isFinite, (1...3600).contains(proposed.timeout), authority.capabilities.contains(proposed.operation.requiredCapability) else { throw InvarError("POLICY_DENIED","Invalid request or missing live session operation capability",exitCode: 8) }
            _ = try await authentication.authority(principal: authority.principal,operation: proposed.operation,policyRevision: authority.policyRevision,capabilityCeiling: authority.capabilities)
            guard let policy = try await repository.loadPolicy(), policy.revision == authority.policyRevision,
                let principal = try await repository.principal(identity: authority.principal) else { throw InvarError("POLICY_DENIED","Request authority changed before envelope issuance",exitCode: 8) }
            let now = Date().timeIntervalSince1970
            let expiry = min(now + min(proposed.timeout,policy.maximumEnvelopeSeconds),principal.expiresAt)
            let fingerprint = try Canonical.identity(proposed.operation)
            let envelope = RequestEnvelope(id: UUID().uuidString,sessionID: authenticated.session.id,capabilities: Array(authority.capabilities),requestKey: proposed.key,principal: authority.principal,workspaceID: workspaceID,fingerprint: fingerprint,operation: proposed.operation.name,daemonEpoch: epoch,policyRevision: authority.policyRevision,expiresAt: expiry,retainUntil: now + retentionSeconds)
            let fixed = try await repository.issueEnvelope(envelope,now: now)
            guard Set(fixed.capabilities).isSubset(of: authority.capabilities) else { throw InvarError("POLICY_DENIED","Original request has a wider scope than this resumed session",exitCode: 8) }
            return try JSONValue.encode(fixed)
        case "request.accept":
            guard channel == .control else { throw InvarError("INVALID_REQUEST","Operation admission requires the control channel") }
            let prepared = try Self.decode(PreparedOperation.self,body)
            guard prepared.envelope.principal == authority.principal, prepared.envelope.workspaceID == workspaceID, prepared.envelope.daemonEpoch == epoch,
                prepared.envelope.policyRevision == authority.policyRevision, prepared.envelope.sessionID != nil, prepared.envelope.watchID == nil,
                Set(prepared.envelope.capabilities).isSubset(of: authority.capabilities), prepared.envelope.capabilities.contains(prepared.operation.requiredCapability) else { throw InvarError("POLICY_DENIED","Fixed operation exceeds the actual connected principal/session",exitCode: 8) }
            let receipt = try await coordinator.submit(prepared.envelope,operation: prepared.operation)
            return try JSONValue.encode(receipt)
        case "formal.query":
            guard channel == .data, authority.capabilities.isSuperset(of: [.read,.sourceValues]) else { throw InvarError("POLICY_DENIED","Private formal queries require read/sourceValues on the data channel",exitCode: 8) }
            guard let formal else { throw InvarError("FORMAL_QUERY_UNSUPPORTED","This host has no configured formal read service",exitCode: 3) }
            let query = try Self.decode(FormalReadQuery.self,body)
            let result = try await formal.query(query,session: authenticated.session,epoch: epoch)
            return try JSONValue.encode(result)
        case "query":
            guard authority.capabilities.contains(.read) else { throw InvarError("POLICY_DENIED","History/status requires read capability",exitCode: 8) }
            let query = try Self.decode(WorkspaceQuery.self,body)
            return try await read(query,authority: authority,channel: channel)
        default: throw InvarError("METHOD_NOT_FOUND","Unknown daemon SDK method",exitCode: 2)
        }
    }
    private func read(_ query: WorkspaceQuery,authority: OperationAuthority,channel: DaemonRPCChannel) async throws -> JSONValue {
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
            _ = try await coordinator.status(receipt.operationID,principal: authority.principal,administrative: false)
            return try JSONValue.encode(receipt)
        case .demand(let id):
            let value = try await coordinator.status(id,principal: authority.principal,administrative: false)
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
            try valuesAllowed(authority)
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
            try valuesAllowed(authority)
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
            guard value.workspaceID == workspaceID, value.principal == authority.principal else { throw InvarError("POLICY_DENIED","Watch belongs to another principal/workspace",exitCode: 8) }
            return try JSONValue.encode(value)
        case .watches:
            let values = try await repository.watches(states: ["registering","active","paused","stopping"])
            return try JSONValue.encode(values.filter { $0.workspaceID == workspaceID && $0.principal == authority.principal })
        case .sourceHead:
            let value = try await repository.sourceHead(workspaceID: workspaceID)
            return try JSONValue.encode(value)
        case .currentView:
            let value = try await repository.latestView(workspaceID: workspaceID)
            return try JSONValue.encode(value)
        case .view(let id):
            try valuesAllowed(authority)
            let value = try await repository.loadView(id)
            guard value.workspaceID == workspaceID else { throw InvarError("POLICY_DENIED","View belongs to another workspace",exitCode: 8) }
            return try JSONValue.encode(value)
        case .evidence(let id):
            try valuesAllowed(authority)
            let value = try await repository.loadEvidence(id)
            try await evidenceAllowed(value)
            return try JSONValue.encode(value)
        case .association(let id):
            try valuesAllowed(authority)
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
    private func valuesAllowed(_ authority: OperationAuthority) throws {
        guard authority.capabilities.contains(.sourceValues) else { throw InvarError("POLICY_DENIED","Raw immutable records may contain source/log/value data and require sourceValues",exitCode: 8) }
    }
    private static func decode<Value: Codable>(_ type: Value.Type,_ value: JSONValue) throws -> Value {
        let decoded = try value.decode(type)
        let encoded = try JSONValue.encode(decoded)
        guard encoded == value else { throw InvarError("INVALID_REQUEST","Unknown or noncanonical typed request fields",exitCode: 2) }
        return decoded
    }
}
