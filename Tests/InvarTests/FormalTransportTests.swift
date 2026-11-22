import ArchitectureCore
import Darwin
import FormalEvidence
import Foundation
import Testing
import VerificationBackends
import VerificationClient
import VerificationCore
import VerificationDaemon
import VerificationDiscovery
import VerificationFormal
import VerificationRuntime
import VerificationStore

@Suite(.timeLimit(.minutes(1))) struct FormalTransportTests {
    struct Environment {
        let owner: DaemonOwnership
        let coordinator: WorkspaceCoordinator
        let readers: FormalReaderRegistry
        let servers: [DaemonRPCServer]
        let tasks: [Task<Void,any Error>]
        let endpoint: LocalDaemonEndpoint
        func shutdown() async throws {
            for server in servers { try await server.shutdown() }
            for task in tasks { task.cancel(); do { try await task.value } catch is CancellationError {} }
            try await coordinator.shutdown(); try await readers.shutdown()
            try await owner.release(); try FileManager.default.removeItem(at: owner.paths.runtimeDirectory)
        }
    }
    static func environment(store: SQLiteVerificationStore,workspaceID: String,engine: String) async throws -> Environment {
        let stateRoot = await store.root
        let paths = DaemonEndpointPaths(workspaceID: workspaceID,userID: getuid(),homeDirectory: FileManager.default.homeDirectoryForCurrentUser,stateDirectory: stateRoot)
        let owner = try DaemonOwnership(paths: paths)
        let epoch = UUID().uuidString
        var servers: [DaemonRPCServer] = [], tasks: [Task<Void,any Error>] = []
        var coordinator: WorkspaceCoordinator?, readers: FormalReaderRegistry?
        var initialized = false
        defer {
            if !initialized {
                for server in servers { do { try await server.shutdown() } catch { Issue.record(error) } }
                for task in tasks { task.cancel(); do { try await task.value } catch is CancellationError {} catch { Issue.record(error) } }
                if let coordinator { do { try await coordinator.shutdown() } catch { Issue.record(error) } }
                if let readers { do { try await readers.shutdown() } catch { Issue.record(error) } }
                do { try await owner.release(); try FileManager.default.removeItem(at: paths.runtimeDirectory) } catch { Issue.record(error) }
            }
        }
        try await store.activateEpoch(epoch,engineIdentity: engine)
        let peer = try ConnectionPeer.current()
        let scheduler = VerificationScheduler(backend: StaticBackend(evaluator: ArchitectureRuleEvaluator()),repository: store)
        let operations = WorkspaceCoordinator(repository: store,scheduler: scheduler,operations: DurableCoordinatorTests.Operations(),epoch: epoch,maximumDemands: 8); coordinator = operations
        let formal = try FormalReaderRegistry(repository: store,workspaceID: workspaceID,epoch: epoch); readers = formal
        let state = DaemonState(workspaceID: workspaceID,epoch: epoch,engineIdentity: engine)
        try await state.transition(to: .recovering); try await state.transition(to: .ready)
        let handler = DaemonRequestDispatcher(workspaceID: workspaceID,epoch: epoch,retentionSeconds: 3600,repository: store,coordinator: operations,state: state,formal: formal)
        let control = try DaemonRPCServer(socket: paths.controlSocket,channel: .control,maximumConnections: 2,handler: handler); servers.append(control)
        let data = try DaemonRPCServer(socket: paths.dataSocket,channel: .data,maximumConnections: 2,handler: handler); servers.append(data)
        for server in servers { tasks.append(Task { try await server.serve() }) }
        let endpoint = LocalDaemonEndpoint(workspaceID: workspaceID,socketPath: paths.controlSocket.path,dataSocketPath: paths.dataSocket.path,serverBinaryDigest: peer.binaryDigest,serverCodeIdentity: peer.codeIdentity,engineIdentity: engine)
        initialized = true
        return Environment(owner: owner,coordinator: operations,readers: formal,servers: servers,tasks: tasks,endpoint: endpoint)
    }
    @Test func localClientsCanReadTheSameFormalEvidenceWithoutConfiguration() async throws {
        let value = try await FormalReaderTests().fixture(shortRetention: false)
        let environment = try await Self.environment(store: value.store,workspaceID: value.workspaceID,engine: String(repeating: "0",count: 64))
        let client = try await LocalVerificationClient.connect(endpoint: environment.endpoint)
        let ordinary = try await LocalVerificationClient.connect(endpoint: environment.endpoint)
        let budget = FormalReadPolicy.development.maximumBudget
        let opener = RemoteFormalEvidenceStore(client: client,evidenceID: value.evidence.id)
        let reader = try await opener.open(value.reference,budget: budget)
        let catalog = try await reader.catalog()
        let graphID = try #require(catalog.graphs.first?.id)
        let page = try await reader.graph(FormalGraphQuery(graphID: graphID,roots: [],relations: [],direction: "outgoing",depth: 0))
        #expect(page.nodes.count == 2)
        #expect(page.nodes.contains { $0.stateValue == .record(["integer":.integer("123456789012345678901234567890"),"text":.string("日本語")]) })
        let second = try await RemoteFormalEvidenceStore(client: ordinary,evidenceID: value.evidence.id).open(value.reference,budget: budget)
        #expect(try await second.catalog() == catalog)
        #expect(await environment.readers.activeCount == 2)
        try await reader.shutdown()
        try await second.shutdown()
        #expect(await environment.readers.activeCount == 0)
        await client.shutdown(); await ordinary.shutdown()
        try await environment.shutdown(); try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root)
    }
}
