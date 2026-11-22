import ArchitectureCore
import Foundation
import VerificationCore
import VerificationFormal

public actor LocalVerificationClient: WorkspaceStatusReading, WorkspaceRequesting, ChangeTracking, VerificationPlanningClient, VerificationRunningClient, EvidenceQuerying, FormalEvidenceQuerying, WatchControlling {
    public nonisolated let endpoint: LocalDaemonEndpoint
    private let maximumCalls: Int
    private var connections: [UUID:LocalConnection] = [:]
    private var inFlight = 0
    private var closed = false
    private var drainWaiters: [CheckedContinuation<Void,Never>] = []
    private init(endpoint: LocalDaemonEndpoint,maximumCalls: Int) { self.endpoint = endpoint; self.maximumCalls = maximumCalls }
    public static func connect(endpoint: LocalDaemonEndpoint,maximumCalls: Int = 8) async throws -> LocalVerificationClient {
        guard (1...32).contains(maximumCalls), !endpoint.workspaceID.isEmpty, endpoint.serverBinaryDigest.utf8.count == 64,
            !endpoint.serverCodeIdentity.isEmpty, endpoint.engineIdentity.utf8.count == 64 else {
            throw InvarError("INVALID_ARGUMENT","Invalid client endpoint or call capacity",exitCode: 2)
        }
        let client = LocalVerificationClient(endpoint: endpoint,maximumCalls: maximumCalls)
        do {
            let status = try await client.status()
            guard status.protocolVersion == 3, status.workspaceID == endpoint.workspaceID,
                status.engineIdentity == endpoint.engineIdentity else {
                throw InvarError("PROTOCOL_MISMATCH","Daemon status differs from its local endpoint")
            }
            return client
        } catch { await client.shutdown(); throw typed(error) }
    }
    public func prepare(_ operation: WorkspaceOperation,key: String,timeout: Double) async throws -> PreparedOperation {
        guard !key.isEmpty, key.utf8.count <= 128, !key.utf8.contains(0), timeout.isFinite, (1...3600).contains(timeout) else { throw InvarError("INVALID_ARGUMENT","Invalid idempotency key or initial deadline",exitCode: 2) }
        let preparation = OperationPreparation(operation: operation,key: key,timeout: timeout)
        let body = try JSONValue.encode(preparation)
        let result = try await exchange("request.prepare",body: body)
        let envelope = try result.decode(RequestEnvelope.self)
        let fingerprint = try Canonical.identity(operation)
        guard envelope.workspaceID == endpoint.workspaceID, envelope.fingerprint == fingerprint,
            envelope.operation == operation.name, envelope.requestKey == key, envelope.watchID == nil else {
            throw InvarError("PROTOCOL_MISMATCH","Fixed request differs from prepared operation")
        }
        return PreparedOperation(envelope: envelope,operation: operation)
    }
    public func accept(_ prepared: PreparedOperation) async throws -> OperationReceipt {
        do {
            guard prepared.envelope.workspaceID == endpoint.workspaceID, prepared.envelope.watchID == nil else {
                throw InvarError("REQUEST_MISMATCH","Prepared request belongs to another workspace or watch")
            }
            let body = try JSONValue.encode(prepared)
            let result = try await exchange("request.accept",body: body)
            let receipt = try result.decode(OperationReceipt.self)
            guard receipt.id == prepared.envelope.id, receipt.fingerprint == prepared.envelope.fingerprint, receipt.daemonEpoch == prepared.envelope.daemonEpoch else { throw InvarError("PROTOCOL_MISMATCH","Receipt changed original request identity") }
            return receipt
        } catch {
            let cause = Self.typed(error)
            throw OperationDeliveryError(prepared: prepared,cause: cause)
        }
    }
    private func submit(_ operation: WorkspaceOperation,key: String,timeout: Double) async throws -> OperationReceipt {
        let prepared = try await prepare(operation,key: key,timeout: timeout)
        return try await accept(prepared)
    }
    public func beginChange(claim: ChangeClaim?,configurationPath: String? = nil,key: String,timeout: Double) async throws -> OperationReceipt { try await submit(.openChange(claim: claim,configurationPath: configurationPath),key: key,timeout: timeout) }
    public func sealChange(_ id: String,key: String,timeout: Double) async throws -> OperationReceipt { try await submit(.sealChange(changeID: id),key: key,timeout: timeout) }
    public func preparePlan(configurationPath: String,changeRevisionID: String?,budget: RunBudget,key: String,timeout: Double) async throws -> OperationReceipt {
        _ = try Canonical.relative(configurationPath); try PlanValidation.budget(budget)
        return try await submit(.preparePlan(configurationPath: configurationPath,changeRevisionID: changeRevisionID,budget: budget),key: key,timeout: timeout)
    }
    public func verify(planID: String,changeRevisionID: String?,replayOfRunID: String?,key: String,timeout: Double) async throws -> OperationReceipt { try await submit(.verify(planID: planID,changeRevisionID: changeRevisionID,replayOfRunID: replayOfRunID),key: key,timeout: timeout) }
    public func cancel(operationID: String,key: String,timeout: Double) async throws -> OperationReceipt { try await submit(.cancel(demandID: operationID),key: key,timeout: timeout) }
    public func registerWatch(configurationPath: String,budget: RunBudget,key: String,timeout: Double) async throws -> OperationReceipt {
        _ = try Canonical.relative(configurationPath); try PlanValidation.budget(budget)
        return try await submit(.watch(configurationPath: configurationPath,budget: budget),key: key,timeout: timeout)
    }
    public func stopWatch(_ id: String,key: String,timeout: Double) async throws -> OperationReceipt { try await submit(.stopWatch(watchID: id),key: key,timeout: timeout) }
    public func watch(_ id: String) async throws -> WatchRecord { try await query(.watch(id: id)) }
    public func watches() async throws -> [WatchRecord] { try await query(.watches) }
    public func status() async throws -> DaemonStatus { try await query(.status) }
    public func receipt(envelopeID: String) async throws -> OperationReceipt? { try await query(.receipt(envelopeID: envelopeID)) }
    public func operation(_ id: String) async throws -> RunDemand { try await query(.demand(id: id)) }
    public func plan(_ id: String) async throws -> PlanSummary { try await query(.plan(id: id)) }
    public func run(_ id: String) async throws -> VerificationRunSummary { try await query(.run(id: id)) }
    public func replay(_ runID: String) async throws -> ReplayComparison? { try await query(.replay(runID: runID)) }
    public func change(_ id: String) async throws -> ChangeRecord { try await query(.change(id: id)) }
    public func changeRevision(_ id: String) async throws -> ChangeRevision { try await query(.changeRevision(id: id)) }
    public func sourceHead() async throws -> SourceHead? { try await query(.sourceHead) }
    public func currentView() async throws -> ViewReference? { try await query(.currentView) }
    public func view(_ id: String) async throws -> ChangeVerificationView { try await query(.view(id: id)) }
    public func runRecord(_ id: String) async throws -> VerificationRun { try await query(.runRecord(id: id)) }
    public func evidenceSummary(_ id: String) async throws -> EvidenceSummary { try await query(.evidenceSummary(id: id)) }
    public func evidence(_ id: String) async throws -> VerificationEvidence { try await query(.evidence(id: id)) }
    public func providerAction(_ id: String) async throws -> ProviderActionSummary? { try await query(.providerAction(id: id)) }
    public func publication(_ demandID: String) async throws -> PublicationSummary? { try await query(.publication(demandID: demandID)) }
    public func association(_ id: String) async throws -> EvidenceAssociation { try await query(.association(id: id)) }
    public func formalQuery(_ query: FormalReadQuery) async throws -> FormalReadResult {
        let body = try JSONValue.encode(query)
        let response = try await exchange("formal.query",body: body,dataChannel: true)
        return try response.decode(FormalReadResult.self)
    }
    private func query<Value: Decodable>(_ request: WorkspaceQuery) async throws -> Value {
        let body = try JSONValue.encode(request)
        let dataChannel: Bool
        switch request { case .status,.receipt,.demand: dataChannel = false; default: dataChannel = true }
        let result = try await exchange("query",body: body,dataChannel: dataChannel)
        do { return try result.decode(Value.self) } catch { throw Self.typed(error) }
    }
    private func exchange(_ method: String,body: JSONValue,dataChannel: Bool = false) async throws -> JSONValue {
        guard !closed, inFlight < maximumCalls else { throw InvarError(closed ? "SESSION_CLOSED" : "RESOURCE_LIMIT","Client is closed or its call capacity is exhausted",exitCode: 6) }
        inFlight += 1; defer { finishCall() }
        let id = UUID(), connection: LocalConnection
        do { connection = try await LocalSocket.connect(path: dataChannel ? endpoint.dataSocketPath : endpoint.socketPath) }
        catch { throw Self.typed(error) }
        connections[id] = connection
        defer { connections.removeValue(forKey: id); await connection.close() }
        guard !closed else { throw InvarError("SESSION_CLOSED","Client closed while connecting") }
        let peer = try await connection.peerIdentity()
        guard peer.binaryDigest == endpoint.serverBinaryDigest, peer.codeIdentity == endpoint.serverCodeIdentity else {
            throw InvarError("EXECUTOR_MISMATCH","Socket server executable differs from the expected daemon",exitCode: 4)
        }
        let request: JSONValue = .object(["id":.string(id.uuidString),"protocolVersion":.number(3),"workspaceID":.string(endpoint.workspaceID),"method":.string(method),"body":body])
        let bytes = try CanonicalJSON.encode(request)
        guard bytes.count <= 65_536 else { throw InvarError("RESOURCE_LIMIT","Typed client request exceeds 64 KiB",exitCode: 6) }
        do {
            try await connection.write(request,timeout: .seconds(5))
            guard let response = try await connection.read(timeout: .seconds(5)), response["id"].string == id.uuidString else { throw InvarError("UNKNOWN_DELIVERY","Daemon closed or returned another response identity",exitCode: 6) }
            if response["error"] != .null {
                let failure = try response["error"].decode(InvarError.self)
                throw failure
            }
            let encoded = try CanonicalJSON.encode(response)
            guard encoded.count <= 1_048_576 else { throw InvarError("RESOURCE_LIMIT","Daemon response exceeds client page budget",exitCode: 6) }
            return response["result"]
        } catch { throw Self.typed(error) }
    }
    private nonisolated static func typed(_ error: any Error) -> InvarError {
        if let value = error as? InvarError { return value }
        if let value = error as? ArchitectureError { return InvarError(value.code,value.message,exitCode: value.exitCode) }
        return InvarError(error is CancellationError ? "CANCELLED" : "CLIENT_FAILURE",String(describing: error),exitCode: error is CancellationError ? 130 : 7)
    }
    private func finishCall() {
        inFlight -= 1
        if closed && inFlight == 0 {
            let waiting = drainWaiters; drainWaiters.removeAll()
            for waiter in waiting { waiter.resume() }
        }
    }
    public func shutdown() async {
        closed = true
        let sockets = Array(connections.values)
        for socket in sockets { await socket.close() }
        if inFlight > 0 { await withCheckedContinuation { drainWaiters.append($0) } }
    }
}
