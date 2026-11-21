import ArchitectureCore
import Darwin
import FormalValidation
import Foundation
import VerificationBackends
import VerificationCore
import VerificationRuntime
import VerificationStore

public actor WorkspaceDaemon: VerificationDaemonServing, DaemonHostControlling {
    private let servicesBuilder: any DaemonServicesBuilding
    private let backend: (any VerificationBackend)?
    private var configuration: DaemonConfiguration?
    private var ownership: DaemonOwnership?
    private var store: SQLiteVerificationStore?
    private var state: DaemonState?
    private var authentication: DaemonSessionAuthority?
    private var formalReaders: FormalReaderRegistry?
    private var coordinator: WorkspaceCoordinator?
    private var services: (any DaemonWorkspaceServices)?
    private var control: DaemonRPCServer?
    private var data: DaemonRPCServer?
    private var epoch: String?
    private var engineIdentity: String?
    private var stop: (DaemonStopMode,ContinuousClock.Instant)?
    private var sourceReadiness = DaemonSourceStatus(.sourceOffline)
    private var recovered = false
    private var stopResponses = Set<String>()
    private var serving = false
    public init(servicesBuilder: any DaemonServicesBuilding,backend: (any VerificationBackend)? = nil) { self.servicesBuilder = servicesBuilder; self.backend = backend }
    public func serve(_ configuration: DaemonConfiguration) async throws {
        guard !serving, ownership == nil else { throw InvarError("DAEMON_ALREADY_RUNNING","Host instance is already serving or still owns incomplete cleanup") }
        serving = true; self.configuration = configuration
        defer { serving = false }
        let ownership = try DaemonOwnership(paths: configuration.paths)
        self.ownership = ownership
        do {
            let files = DaemonPrivateFiles(paths: configuration.paths)
            if !configuration.explicitStart, FileManager.default.fileExists(atPath: configuration.paths.stopLatch.path) { throw InvarError("USER_STOPPED","Explicit user stop prevents automatic activation",exitCode: 6) }
            if !configuration.explicitStart,
                !FileManager.default.fileExists(atPath: configuration.paths.stateDirectory.appendingPathComponent("verification.sqlite").path) {
                throw InvarError("APPROVAL_REQUIRED", "Start Invar and configure the workspace policy before automatic activation", exitCode: 8)
            }
            let store = try SQLiteVerificationStore(root: configuration.paths.stateDirectory,policy: configuration.storePolicy)
            self.store = store
            try files.prepare(explicitStart: configuration.explicitStart)
            let engine = try ExecutionIdentity.current(executable: configuration.executable), epoch = UUID().uuidString
            self.epoch = epoch; engineIdentity = engine
            var policy = try await store.loadPolicy()
            if !configuration.explicitStart {
                guard let policy else { throw InvarError("APPROVAL_REQUIRED", "Automatic activation requires a stored workspace policy", exitCode: 8) }
                guard policy.engineIdentity == engine else { throw InvarError("EXECUTOR_MISMATCH", "The stored policy belongs to another Invar engine", exitCode: 8) }
            }
            try await store.activateEpoch(epoch,engineIdentity: engine)
            if let initial = configuration.initialPolicy {
                guard initial.engineIdentity == engine else { throw InvarError("EXECUTOR_MISMATCH","Initial host policy names another engine") }
                if let policy { guard initial == policy else { throw InvarError("REVISION_CONFLICT","Use host.policy.apply to change an existing policy") } }
                else { try await store.savePolicy(initial,expectedRevision: 0); policy = initial }
            }
            let state = DaemonState(workspaceID: configuration.paths.workspaceID,epoch: epoch,engineIdentity: engine,policyRevision: policy?.revision ?? 0)
            self.state = state; try await state.transition(to: .recovering)
            let resources = ResourcePool(policy: configuration.schedulingPolicy)
            let services = try await servicesBuilder.make(configuration: configuration,repository: store,epoch: epoch,engineIdentity: engine,resources: resources)
            self.services = services
            let authentication = DaemonSessionAuthority(repository: store,epoch: epoch); self.authentication = authentication
            let scheduler = VerificationScheduler(backend: backend ?? IsolatedBackendExecutor(executable: configuration.executable),repository: store,applicability: services,policy: configuration.schedulingPolicy,resources: resources)
            let coordinator = WorkspaceCoordinator(repository: store,scheduler: scheduler,authorization: authentication,operations: services,epoch: epoch,maximumDemands: configuration.maximumDemands,acceptingRequests: false,publisher: services as? any VerificationPublishing,external: services as? any ExternalAdmissionAuthorizing)
            self.coordinator = coordinator
            if let managed = services as? any DaemonManagedServices { try await managed.bind(coordinator: coordinator,authentication: authentication) }
            let formal = try FormalReaderRegistry(repository: store,workspaceID: configuration.paths.workspaceID,epoch: epoch,policy: configuration.formalReadPolicy)
            formalReaders = formal
            let application = DaemonRequestDispatcher(workspaceID: configuration.paths.workspaceID,epoch: epoch,retentionSeconds: configuration.storePolicy.retentionSeconds,repository: store,coordinator: coordinator,authentication: authentication,state: state,formal: formal)
            let peer = try ConnectionPeer.current()
            var birth = proc_bsdinfo()
            guard proc_pidinfo(getpid(),PROC_PIDTBSDINFO,0,&birth,Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { throw InvarError("OWNERSHIP_FAILED","Cannot establish host process start identity") }
            var audit = [Int32](repeating: 0,count: 8), count = mach_msg_type_number_t(8)
            let auditStatus = audit.withUnsafeMutableBufferPointer { buffer in
                task_info(mach_task_self_,task_flavor_t(TASK_AUDIT_TOKEN),buffer.baseAddress!,&count)
            }
            guard auditStatus == KERN_SUCCESS, count == 8 else { throw InvarError("OWNERSHIP_FAILED","Cannot establish kernel host audit identity") }
            let auditIdentity = audit.withUnsafeBytes { Data($0).base64EncodedString() }
            let endpoint = LocalDaemonEndpoint(workspaceID: configuration.paths.workspaceID,socketPath: configuration.paths.controlSocket.path,dataSocketPath: configuration.paths.dataSocket.path,serverBinaryDigest: peer.binaryDigest,serverCodeIdentity: peer.codeIdentity,engineIdentity: engine)
            let record = DaemonHostRecord(stateDirectory: configuration.paths.stateDirectory.path,epoch: epoch,endpoint: endpoint,auditIdentity: auditIdentity,processID: getpid(),startSeconds: birth.pbi_start_tvsec,startMicroseconds: birth.pbi_start_tvusec,administrativeCredential: UUID().uuidString + UUID().uuidString)
            let handler = DaemonHostDispatcher(record: record,host: self,application: application)
            let control = try DaemonRPCServer(socket: configuration.paths.controlSocket,channel: .control,maximumConnections: configuration.controlConnections,handler: handler); self.control = control
            let data = try DaemonRPCServer(socket: configuration.paths.dataSocket,channel: .data,maximumConnections: configuration.dataConnections,handler: handler); self.data = data
            try files.publish(record)
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await control.serve() }
                group.addTask { try await data.serve() }
                group.addTask { try await self.runWorkspace() }
                defer { group.cancelAll() }
                _ = try await group.next()
            }
            try await finish()
        } catch {
            let original = error
            do { try await finish() }
            catch { throw InvarError("RECOVERY_BLOCKED","Host failed (\(original)); shutdown is incomplete (\(error))",exitCode: 6) }
            throw original
        }
    }
    private func runWorkspace() async throws {
        guard let store, let state, let coordinator, let services else { throw InvarError("INVALID_TRANSITION","Host composition is incomplete") }
        var blocked = false
        do {
            try await recoverExecutions(store)
            try await recoverReservations(store)
            let readiness = try await withThrowingTaskGroup(of: DaemonSourceStatus?.self) { group in
                group.addTask { try await services.start() }
                group.addTask {
                    while !(await self.isStopping) { try await Task.sleep(for: .milliseconds(10)) }
                    return nil
                }
                defer { group.cancelAll() }
                return try await group.next() ?? nil
            }
            if let readiness { sourceReadiness = readiness }
            try await coordinator.recover()
            recovered = true
            if stop == nil {
                try await coordinator.openAdmission()
                if let managed = services as? any DaemonManagedServices { try await managed.activate() }
                try await refreshPhase()
            }
        } catch {
            let failure = error
            await coordinator.closeAdmission(); await services.closeAdmission()
            do { try await coordinator.shutdown() }
            catch { throw InvarError("RECOVERY_BLOCKED","Recovery failed (\(failure)); task cleanup failed (\(error))",exitCode: 6) }
            if Task.isCancelled { throw CancellationError() }
            blocked = true
            try await state.transition(to: .recoveryBlocked,diagnostics: [String(describing: failure).prefix(1024).description])
        }
        while stop == nil {
            try Task.checkCancellation()
            try await formalReaders?.expire()
            let current = await services.sourceStatus()
            if !blocked, current != sourceReadiness { sourceReadiness = current; try await refreshPhase() }
            try await Task.sleep(for: .milliseconds(50))
        }
        try await drainStopResponses()
        try await state.transition(to: .draining)
        await coordinator.closeAdmission(); await services.closeAdmission()
        if let (mode,deadline) = stop, mode == .drain {
            while await coordinator.activeCount > 0, ContinuousClock.now < deadline {
                try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(10))
            }
        }
        try await coordinator.shutdown(); try await services.shutdown()
    }
    private var isStopping: Bool { stop != nil }
    private func recoverExecutions(_ store: SQLiteVerificationStore) async throws {
        try await store.recoverRetiredObjects()
        for execution in try await store.pendingExecutions() {
            let output = try await store.outputRoot(for: execution.id)
            let directory = output.appendingPathComponent("native-processes")
            if FileManager.default.fileExists(atPath: directory.path) {
                let journal = try ToolLaunchJournal(directory: directory,artifactRoot: output.appendingPathComponent("native"))
                try await journal.recover()
            }
            try await WorkerLifetime.verifyStopped(beneath: output)
            let interrupted = ExecutionRecord(id: execution.id,descriptorID: execution.descriptorID,inputKey: execution.inputKey,planID: execution.planID,jobID: execution.jobID,state: "interrupted",revision: execution.revision+1,evidenceID: nil,failure: InvarError("INTERRUPTED","Prior daemon did not commit terminal evidence",exitCode: 6))
            try await store.saveExecution(interrupted,expectedRevision: execution.revision)
            try await store.releaseReservation(execution.id)
        }
    }
    private func recoverReservations(_ store: SQLiteVerificationStore) async throws {
        for reservation in try await store.storageReservations() {
            guard let output = try await store.abandonedReservationRoot(reservation.id) else { continue }
            let directory = output.appendingPathComponent("native-processes")
            if FileManager.default.fileExists(atPath: directory.path) {
                let journal = try ToolLaunchJournal(directory: directory,artifactRoot: output.appendingPathComponent("native"))
                try await journal.recover()
            }
            try await WorkerLifetime.verifyStopped(beneath: output)
            try await store.discardAbandonedReservation(reservation.id)
        }
    }
    private func refreshPhase() async throws {
        guard recovered, stop == nil, let state, let store else { return }
        let policy = try await store.loadPolicy()
        let phase: DaemonState.Phase = policy == nil || sourceReadiness.readiness == .approvalRequired ? .approvalRequired : sourceReadiness.readiness == .ready ? .ready : .sourceOffline
        try await state.transition(to: phase,diagnostics: sourceReadiness.diagnostics)
    }
    func administrativeStatus() async throws -> DaemonStatus {
        guard let state else { throw InvarError("DAEMON_STARTING","Host status is not available yet",exitCode: 6) }
        let watches: [WatchRecord]
        if let store { watches = try await store.watches(states: ["registering","active","paused","stopping"]) } else { watches = [] }
        return await state.status(activeOperations: coordinator?.activeCount ?? 0,watchCount: watches.count)
    }
    func requestStop(mode: DaemonStopMode,deadlineSeconds: Double,requestID: String) async throws -> DaemonStatus {
        guard let configuration, let state, deadlineSeconds.isFinite, (1...300).contains(deadlineSeconds) else { throw InvarError("INVALID_REQUEST","Stop deadline must be 1...300 seconds") }
        stopResponses.insert(requestID)
        if stop == nil {
            try DaemonPrivateFiles(paths: configuration.paths).stopLatch()
            stop = (mode,ContinuousClock.now.advanced(by: .seconds(deadlineSeconds)))
            try await state.transition(to: .draining)
            await coordinator?.closeAdmission()
        }
        return try await administrativeStatus()
    }
    func stopResponseFinished(requestID: String) { stopResponses.remove(requestID) }
    private func drainStopResponses() async throws {
        while !stopResponses.isEmpty { try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(2)) }
    }
    func installPolicy(_ policy: WorkspacePolicy,expectedRevision: Int) async throws -> DaemonStatus {
        guard stop == nil, let store, let configuration, let engineIdentity, policy.workspaceID == configuration.paths.workspaceID, policy.engineIdentity == engineIdentity,
            configuration.controlConnections + configuration.dataConnections <= policy.maximumConnections else { throw InvarError("POLICY_DENIED","Policy differs from this live host or admission is stopped",exitCode: 8) }
        try await store.savePolicy(policy,expectedRevision: expectedRevision)
        await authentication?.invalidate(); try await state?.policyChanged(revision: policy.revision)
        try await refreshPhase()
        return try await administrativeStatus()
    }
    private func finish() async throws {
        if let state { try await state.transition(to: .draining) }
        do {
            await coordinator?.closeAdmission(); await services?.closeAdmission()
            try await control?.shutdown(); try await data?.shutdown()
            try await coordinator?.shutdown(); try await services?.shutdown(); await authentication?.shutdown()
            try await formalReaders?.shutdown()
            try await store?.shutdown(); store = nil
            if let configuration, let epoch { try DaemonPrivateFiles(paths: configuration.paths).removeRecord(epoch: epoch) }
            if let state { try await state.transition(to: .stopped) }
            try await ownership?.release(); ownership = nil
        } catch {
            try await state?.transition(to: .recoveryBlocked,diagnostics: ["Host cleanup is incomplete"])
            throw error
        }
    }
}
