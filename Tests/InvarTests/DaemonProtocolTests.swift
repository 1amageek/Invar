import ArchitectureCore
import Foundation
import Darwin
import Testing
import VerificationBackends
import VerificationClient
import VerificationCore
import VerificationDaemon
import VerificationDiscovery
import VerificationRuntime
import VerificationStore

@Suite(.timeLimit(.minutes(1))) struct DaemonProtocolTests {
    struct Environment {
        let root: URL
        let ownership: DaemonOwnership
        let store: SQLiteVerificationStore
        let plan: VerificationPlan
        let authentication: DaemonSessionAuthority
        let coordinator: WorkspaceCoordinator
        let control: DaemonRPCServer
        let data: DaemonRPCServer
        let tasks: [Task<Void,any Error>]
        let endpoint: LocalDaemonEndpoint
        func shutdown() async throws {
            try await control.shutdown(); try await data.shutdown()
            for task in tasks {
                task.cancel()
                do { try await task.value } catch is CancellationError {}
            }
            try await coordinator.shutdown(); await authentication.shutdown(); try await store.shutdown()
            try await ownership.release()
            try FileManager.default.removeItem(at: ownership.paths.runtimeDirectory)
            try FileManager.default.removeItem(at: root)
        }
    }
    struct Operations: WorkspaceOperationExecuting {
        func execute(_ demand: RunDemand,authority: OperationAuthority) throws -> String { throw InvarError("UNSUPPORTED_OPERATION","Protocol fixture owns prepublished verification plans only",exitCode: 3) }
    }
    func environment(capabilities: Set<WorkspaceCapability> = [.read,.verification,.sourceValues],sessionSeconds: Double = 60) async throws -> Environment {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-protocol-" + UUID().uuidString)
        var initialized = false
        var startupOwner: DaemonOwnership?, startupStore: SQLiteVerificationStore?, startupAuthentication: DaemonSessionAuthority?, startupCoordinator: WorkspaceCoordinator?
        var startupServers: [DaemonRPCServer] = [], startupTasks: [Task<Void,any Error>] = []
        defer {
            if !initialized {
                for server in startupServers { do { try await server.shutdown() } catch { Issue.record(error) } }
                for task in startupTasks { task.cancel(); do { try await task.value } catch is CancellationError {} catch { Issue.record(error) } }
                if let startupCoordinator { do { try await startupCoordinator.shutdown() } catch { Issue.record(error) } }
                if let startupAuthentication { await startupAuthentication.shutdown() }
                if let startupStore { do { try await startupStore.shutdown() } catch { Issue.record(error) } }
                if let startupOwner { do { try await startupOwner.release(); try FileManager.default.removeItem(at: startupOwner.paths.runtimeDirectory) } catch { Issue.record(error) } }
                if FileManager.default.fileExists(atPath: root.path) { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            }
        }
        let workspace = root.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace,withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700])
        let upstream = try WorkspacePaths(workspace.path)
        let stateRoot = try DaemonPathValidation.stateRoot(root.appendingPathComponent("state"),outside: workspace)
        let paths = DaemonEndpointPaths(workspaceID: upstream.workspaceID,userID: getuid(),homeDirectory: FileManager.default.homeDirectoryForCurrentUser,stateDirectory: stateRoot)
        let ownership = try DaemonOwnership(paths: paths); startupOwner = ownership
        let store = try SQLiteVerificationStore(root: stateRoot); startupStore = store
        let fixture = DomainTests.inventory()
        let inventory = ScopeInventory(workspaceID: upstream.workspaceID,snapshotID: "fixed-source",contextDigest: fixture.contextDigest,metadata: [:],entities: fixture.entities,facts: fixture.facts,coverage: fixture.coverage,inputs: [])
        _ = try await store.saveInput(CapturedWorkspace(inventory: inventory,files: [:]))
        let job = SchedulerTests.job("acyclic"), engine = String(repeating: "0",count: 64)
        let configuration = VerificationConfiguration(architecture: [job.policy!])
        let body = PlanBody(input: try VerificationInput.reference(inventory),executorIdentity: engine,configurationDigest: try configuration.identity(),jobs: [job],budget: RunBudget())
        let plan = VerificationPlan(id: try Canonical.identity(body),body: body)
        try await store.savePlan(plan)
        let peer = try ConnectionPeer.current(), epoch = UUID().uuidString
        let policy = WorkspacePolicy(workspaceID: upstream.workspaceID,engineIdentity: engine,revision: 1,peers: [PeerGrant(binaryDigest: peer.binaryDigest,capabilities: capabilities)],approvals: [ContractApproval(configurationDigest: plan.body.configurationDigest,entries: [])],sessionSeconds: sessionSeconds,principalSeconds: 120,maximumSessions: 16,maximumConnections: 8,maximumEnvelopeSeconds: 60)
        try await store.savePolicy(policy,expectedRevision: 0); try await store.activateEpoch(epoch,engineIdentity: engine)
        _ = try await store.observeInput(plan.body.input,epoch: epoch)
        let authentication = DaemonSessionAuthority(repository: store,epoch: epoch); startupAuthentication = authentication
        let scheduler = VerificationScheduler(backend: StaticBackend(evaluator: ArchitectureRuleEvaluator()),repository: store,applicability: SchedulerTests.Current(value: "matchesInputs"))
        let coordinator = WorkspaceCoordinator(repository: store,scheduler: scheduler,authorization: authentication,operations: Operations(),epoch: epoch,maximumDemands: 8)
        startupCoordinator = coordinator
        let state = DaemonState(workspaceID: upstream.workspaceID,epoch: epoch,engineIdentity: engine,policyRevision: 1)
        try await state.transition(to: .recovering); try await state.transition(to: .ready)
        let handler = DaemonRequestDispatcher(workspaceID: upstream.workspaceID,epoch: epoch,retentionSeconds: 3600,repository: store,coordinator: coordinator,authentication: authentication,state: state)
        let control = try DaemonRPCServer(socket: paths.controlSocket,channel: .control,maximumConnections: 4,handler: handler)
        startupServers.append(control)
        let data = try DaemonRPCServer(socket: paths.dataSocket,channel: .data,maximumConnections: 4,handler: handler)
        startupServers.append(data)
        let tasks = [Task { try await control.serve() },Task { try await data.serve() }]; startupTasks = tasks
        let endpoint = LocalDaemonEndpoint(workspaceID: upstream.workspaceID,socketPath: paths.controlSocket.path,dataSocketPath: paths.dataSocket.path,serverBinaryDigest: peer.binaryDigest,serverCodeIdentity: peer.codeIdentity,engineIdentity: engine)
        initialized = true
        return Environment(root: root,ownership: ownership,store: store,plan: plan,authentication: authentication,coordinator: coordinator,control: control,data: data,tasks: tasks,endpoint: endpoint)
    }
    func wait(_ receipt: OperationReceipt,client: LocalVerificationClient) async throws -> RunDemand {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while true {
            let operation = try await client.operation(receipt.operationID)
            if !["queued","running","cancelling"].contains(operation.state) { return operation }
            guard ContinuousClock.now < deadline else { throw InvarError("TEST_DEADLINE","Protocol operation did not finish") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    @Test func realAuthenticationAndReceiptsLeadToOneSharedCommittedEvidenceView() async throws {
        let environment = try await environment()
        defer { do { try await environment.shutdown() } catch { Issue.record(error) } }
        let a = try await LocalVerificationClient.connect(endpoint: environment.endpoint,label: "agent-a",capabilities: [.read,.verification,.sourceValues])
        let b = try await LocalVerificationClient.connect(endpoint: environment.endpoint,label: "agent-b",capabilities: [.read,.verification,.sourceValues])
        defer { await a.shutdown(); await b.shutdown() }
        #expect(try await a.session().principal != b.session().principal)
        async let first = a.verify(planID: environment.plan.id,changeRevisionID: nil,replayOfRunID: nil,key: "a",timeout: 30)
        async let second = b.verify(planID: environment.plan.id,changeRevisionID: nil,replayOfRunID: nil,key: "b",timeout: 30)
        let receipts = try await [first,second]
        #expect(receipts[0].operationID != receipts[1].operationID)
        let firstRun = try await wait(receipts[0],client: a), secondRun = try await wait(receipts[1],client: b)
        #expect(firstRun.state == "completed" && secondRun.state == "completed")
        let firstID = try #require(firstRun.resultID), secondID = try #require(secondRun.resultID)
        let summaryA = try await a.run(firstID), summaryB = try await b.run(secondID)
        await #expect(throws: InvarError.self) { try await a.prepare(.reconcile(planID: environment.plan.id,runID: firstID),key: "internal-watch-only",timeout: 10) }
        #expect(summaryA.acceptedAtCompletion && summaryB.acceptedAtCompletion)
        #expect(summaryA.historical && summaryB.historical)
        #expect(summaryA.attempts.map(\.evidenceID) == summaryB.attempts.map(\.evidenceID))
        #expect(try await a.currentView() == nil)
        #expect(try await b.currentView() == nil)
        let referenceA = try #require(firstRun.view), referenceB = try #require(secondRun.view)
        let viewA = try await a.view(referenceA.id), viewB = try await b.view(referenceB.id)
        #expect(viewA.evidenceIDs == viewB.evidenceIDs)
        #expect(try viewA.reference() == referenceA)
        await #expect(throws: InvarError.self) { try await b.receipt(envelopeID: receipts[0].id) }
        #expect(try await a.status().state == "ready")
    }
    @Test func ordinaryReadGetsCommittedAxesWithoutPrivateScopeLogsOrValues() async throws {
        let environment = try await environment()
        defer { do { try await environment.shutdown() } catch { Issue.record(error) } }
        let client = try await LocalVerificationClient.connect(endpoint: environment.endpoint,label: "administrator",capabilities: [.read,.verification,.nativeExecution])
        defer { await client.shutdown() }
        #expect(try await client.session().grants == ["read","verification"])
        let receipt = try await client.verify(planID: environment.plan.id,changeRevisionID: nil,replayOfRunID: nil,key: "readable",timeout: 30)
        let operation = try await wait(receipt,client: client), id = try #require(operation.resultID)
        let summary = try await client.run(id)
        #expect(summary.acceptedAtCompletion)
        await #expect(throws: InvarError.self) { try await client.runRecord(id) }
        let source = try #require(try await client.sourceHead())
        #expect(source.confirmed && source.input.workspaceID == environment.endpoint.workspaceID)
        _ = try await environment.store.invalidateSource(workspaceID: source.workspaceID,epoch: source.daemonEpoch,reason: "Source observation became uncertain")
        #expect(try await client.sourceHead()?.confirmed == false)
        #expect(try await client.currentView() == nil)
        let secret = "PRIVATE_SOURCE_LOG_VALUE"
        let evidence = VerificationEvidence(inputID: environment.plan.body.input.id,jobID: "acyclic",execution: "completed",outcome: "holdsWithinScope",domain: "architecture",translation: "notApplicable",scope: secret,adequacy: "completeWithinScope",detail: secret,resources: ["privateValue":42,"wallSeconds":0.1],startedAt: "now",finishedAt: "now")
        try await environment.store.saveEvidence(evidence)
        let projected = try await client.evidenceSummary(evidence.id)
        let bytes = try Canonical.encode(projected)
        #expect(String(decoding: bytes,as: UTF8.self).contains(secret) == false)
        #expect(projected.evidenceID == evidence.id && projected.outcome == evidence.outcome)
        #expect(projected.resources == ["wallSeconds":0.1])
        await #expect(throws: InvarError.self) { try await client.evidence(evidence.id) }
        let readonly = try await LocalVerificationClient.connect(endpoint: environment.endpoint,capabilities: [.read])
        defer { await readonly.shutdown() }
        let request = WorkspaceOperation.verify(planID: environment.plan.id,changeRevisionID: nil,replayOfRunID: nil)
        await #expect(throws: InvarError.self) { try await readonly.prepare(request,key: "forbidden",timeout: 20) }
    }
}

extension DaemonProtocolTests {
    func raw(_ environment: Environment,method: String,body: JSONValue,credential: String? = nil,epoch: String? = nil) async throws -> JSONValue {
        let connection = try await LocalSocket.connect(path: environment.endpoint.socketPath)
        defer { await connection.close() }
        let id = UUID().uuidString
        let request: JSONValue = .object(["id":.string(id),"protocolVersion":.number(2),"workspaceID":.string(environment.endpoint.workspaceID),"method":.string(method),"epoch":epoch.map(JSONValue.string) ?? .null,"credential":credential.map(JSONValue.string) ?? .null,"body":body])
        try await connection.write(request,timeout: .seconds(5))
        let response = try #require(try await connection.read(timeout: .seconds(5)))
        #expect(response["id"].string == id)
        return response
    }
    @Test func actualDispatcherRejectsPayloadAuthorityFlagsAndBulkQueriesOnControl() async throws {
        let environment = try await environment()
        defer { do { try await environment.shutdown() } catch { Issue.record(error) } }
        let opened = try await raw(environment,method: "session.open",body: .object(["label":.string("host user"),"capabilities":.array([.string("read"),.string("verification")]),"resumeCredential":.null]))
        let grant = try opened["result"].decode(ClientSessionGrant.self)
        let preparation = OperationPreparation(operation: .verify(planID: environment.plan.id,changeRevisionID: nil,replayOfRunID: nil),key: "injected",timeout: 20)
        let encoded = try JSONValue.encode(preparation)
        guard case .object(var fields) = encoded else { throw InvarError("INVALID_FIXTURE","Preparation is not an object") }
        fields["nativeExecutionAllowed"] = .bool(true)
        let rejected = try await raw(environment,method: "request.prepare",body: .object(fields),credential: grant.credential,epoch: grant.epoch)
        #expect(rejected["error"]["code"].string == "INVALID_REQUEST")
        #expect(try await environment.store.pendingDemands().isEmpty)
        let query = try JSONValue.encode(WorkspaceQuery.plan(id: environment.plan.id))
        let wrongChannel = try await raw(environment,method: "query",body: query,credential: grant.credential,epoch: grant.epoch)
        #expect(wrongChannel["error"]["code"].string == "INVALID_REQUEST")
    }
    @Test func watchQueriesUseCommittedHeadsAndOriginalPrincipalOverActualAuthenticatedSockets() async throws {
        let environment = try await environment(capabilities: [.read,.verification,.planning,.watching])
        defer { do { try await environment.shutdown() } catch { Issue.record(error) } }
        let owner = try await LocalVerificationClient.connect(endpoint: environment.endpoint,capabilities: [.read,.verification,.planning,.watching])
        let other = try await LocalVerificationClient.connect(endpoint: environment.endpoint,capabilities: [.read])
        defer { await owner.shutdown(); await other.shutdown() }
        let prepared = try await owner.prepare(.watch(configurationPath: "contracts.json",budget: RunBudget()),key: "watch-record",timeout: 15)
        // This transport test supplies a committed registration without claiming a source-monitor implementation.
        let envelope = prepared.envelope
        let queued = RunDemand(id: Canonical.parts("invar.operation/2",[envelope.id]),envelopeID: envelope.id,principal: envelope.principal,origin: "internal",request: prepared.operation,planID: nil,changeRevisionID: nil,state: "queued",revision: 1,executionIDs: [],resultID: nil,failure: nil)
        _ = try await environment.store.acceptDemand(envelope,demand: queued,now: Date().timeIntervalSince1970)
        let running = queued.transitioning(to: "running")
        try await environment.store.transitionDemand(running,expectedRevision: queued.revision)
        let principal = try #require(try await environment.store.principal(identity: envelope.principal))
        let record = WatchRecord(id: queued.id,envelopeID: envelope.id,workspaceID: envelope.workspaceID,principal: envelope.principal,policyRevision: envelope.policyRevision,capabilities: envelope.capabilities,configurationPath: "contracts.json",budget: RunBudget(),expiresAt: principal.expiresAt)
        try await environment.store.createWatch(record)
        try await environment.store.completeDemand(running.transitioning(to: "completed",resultID: record.id),run: nil,view: nil,expectedRevision: running.revision)
        let retained = try await environment.store.loadWatch(record.id)
        #expect(try await owner.watch(record.id) == retained)
        #expect(try await owner.watches() == [retained])
        #expect(try await owner.status().watchCount == 1)
        #expect(try await other.watches().isEmpty)
        await #expect(throws: InvarError.self) { try await other.watch(record.id) }
        await #expect(throws: InvarError.self) { try await other.stopWatch(record.id,key: "forbidden-stop",timeout: 10) }
        let stopped = retained.revising(state: "stopped")
        try await environment.store.saveWatch(stopped,expectedRevision: retained.revision)
        #expect(try await owner.watches().isEmpty)
        #expect(try await owner.watch(record.id) == stopped)
        #expect(try await owner.status().watchCount == 0)
    }

}
