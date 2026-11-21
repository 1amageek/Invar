import VerificationCore
import VerificationExplorer
import VerificationRuntime

actor ExplorerDaemonServices: DaemonWorkspaceServices, DaemonManagedServices, VerificationPublishing, ExternalAdmissionAuthorizing {
    private let connection: ExplorerProviderConnection
    private let operations: WorkspaceOperations
    private let publisher: ExplorerPublisher
    private let repository: any VerificationRepository
    private let workspaceID: String
    private let epoch: String
    private let watchPolicy: WatchPolicy
    private let resources: any WorkspaceResourceAdmitting
    private let retentionSeconds: Double
    private var actions: ProviderActionRuntime?
    private var watches: WatchRegistry?
    init(connection: ExplorerProviderConnection,operations: WorkspaceOperations,publisher: ExplorerPublisher,repository: any VerificationRepository,workspaceID: String,epoch: String,watchPolicy: WatchPolicy,resources: any WorkspaceResourceAdmitting,retentionSeconds: Double) {
        self.connection = connection; self.operations = operations; self.publisher = publisher
        self.resources = resources; self.retentionSeconds = retentionSeconds
        self.repository = repository; self.workspaceID = workspaceID; self.epoch = epoch; self.watchPolicy = watchPolicy
    }
    func bind(coordinator: any WorkspaceCoordinating,authentication: any DaemonAuthenticating) async throws {
        guard watches == nil else { throw InvarError("INVALID_TRANSITION","Explorer services already own a watch registry") }
        guard let external = coordinator as? any ExternalWorkspaceCoordinating else { throw InvarError("UNSUPPORTED_CAPABILITY","Provider service requires an external admission coordinator") }
        actions = ProviderActionRuntime(operations: operations,connection: connection,repository: repository,authentication: authentication,coordinator: external,resources: resources,epoch: epoch,retentionSeconds: retentionSeconds)
        watches = try WatchRegistry(repository: repository,coordinator: coordinator,events: ExplorerSourceEvents(connection: connection),probe: operations,workspaceID: workspaceID,epoch: epoch,policy: watchPolicy)
    }
    func activate() async throws {
        guard let watches else { throw InvarError("INVALID_TRANSITION","Watch registry has not been bound") }
        try await watches.start()
        try await actions?.start()
    }
    func start() async throws -> DaemonSourceStatus {
        let status = try await connection.start(); try await publisher.start(); return Self.convert(status)
    }
    func sourceStatus() async -> DaemonSourceStatus {
        let source = Self.convert(await connection.status())
        let diagnostic = await publisher.diagnostic()
        let actionDiagnostic = await actions?.diagnostic()
        let watchDiagnostics = await watches?.diagnostics() ?? []
        let monitoring = await watches?.available() ?? false
        return DaemonSourceStatus(source.readiness == .ready && !monitoring ? .sourceOffline : source.readiness,diagnostics: source.diagnostics + (diagnostic.map { [$0.code + ": " + $0.message] } ?? []) + (actionDiagnostic.map { [$0.code + ": " + $0.message] } ?? []) + watchDiagnostics.map { $0.code + ": " + $0.message })
    }
    private static func convert(_ status: ExplorerConnectionStatus) -> DaemonSourceStatus {
        let readiness: DaemonSourceReadiness
        switch status.state { case .ready: readiness = .ready; case .sourceOffline: readiness = .sourceOffline; case .approvalRequired: readiness = .approvalRequired }
        return DaemonSourceStatus(readiness,diagnostics: status.failure.map { [$0.code + ": " + $0.message] } ?? [])
    }
    func execute(_ demand: RunDemand,authority: OperationAuthority) async throws -> String {
        switch demand.request {
        case .watch,.stopWatch:
            guard let watches else { throw InvarError("INVALID_TRANSITION","Watch registry has not been bound") }
            return try await watches.execute(demand,authority: authority)
        default: return try await operations.execute(demand,authority: authority)
        }
    }
    func applicability(of plan: SchedulingPlan) async throws -> InputComparison { try await operations.applicability(of: plan) }
    func takeStart(_ actionID: String) async throws -> ExternalAdmission {
        guard let actions else { throw InvarError("COORDINATOR_STOPPED","Provider Action admission is not bound") }
        return try await actions.takeStart(actionID)
    }
    func closeAdmission() async { await actions?.closeAdmission(); await watches?.closeAdmission(); await operations.closeAdmission() }
    func reserve(demand: RunDemand,plan: SchedulingPlan) async throws { try await publisher.reserve(demand: demand,plan: plan) }
    func prepare(demand: RunDemand,run: VerificationRun,view: ChangeVerificationView) async throws -> PublicationRecord { try await publisher.prepare(demand: demand,run: run,view: view) }
    func abandon(demandID: String,failure: InvarError) async throws { try await publisher.abandon(demandID: demandID,failure: failure) }
    func shutdown() async throws { await actions?.closeAdmission(); try await watches?.shutdown(); await operations.shutdown(); await publisher.shutdown(); try await connection.shutdown() }
}
