import ArchitectureCore
import Foundation
import Testing
import VerificationBackends
import VerificationClient
import VerificationCore
import VerificationDaemon
import VerificationDiscovery
import VerificationRuntime

@Suite(.timeLimit(.minutes(1))) struct DaemonLifecycleTests {
    actor Services: DaemonWorkspaceServices {
        let configuration: DaemonConfiguration
        let repository: any VerificationRepository
        let epoch: String
        let engine: String
        let availability: DaemonSourceReadiness
        var planID: String?
        var stopped = false
        init(configuration: DaemonConfiguration,repository: any VerificationRepository,epoch: String,engine: String,availability: DaemonSourceReadiness) {
            self.configuration = configuration; self.repository = repository; self.epoch = epoch; self.engine = engine; self.availability = availability
        }
        func start() async throws -> DaemonSourceStatus {
            let original = DomainTests.inventory()
            let inventory = ScopeInventory(workspaceID: configuration.paths.workspaceID,snapshotID: original.snapshotID,contextDigest: original.contextDigest,metadata: original.metadata,entities: original.entities,facts: original.facts,coverage: original.coverage,inputs: [],diagnostics: [])
            _ = try await repository.saveInput(CapturedWorkspace(inventory: inventory,files: [:]))
            let input = try VerificationInput.reference(inventory)
            _ = try await repository.observeInput(input,epoch: epoch)
            let job = SchedulerTests.job("cycle")
            let digest = try VerificationConfiguration(architecture: [try #require(job.policy)]).identity()
            let body = PlanBody(input: input,executorIdentity: engine,configurationDigest: digest,jobs: [job],budget: RunBudget())
            let plan = VerificationPlan(id: try Canonical.identity(body),body: body)
            try await repository.savePlan(plan); planID = plan.id
            return DaemonSourceStatus(availability)
        }
        func execute(_ demand: RunDemand) throws -> String { throw InvarError("UNSUPPORTED_OPERATION","Lifecycle fixture prepublishes one static plan") }
        func applicability(of plan: SchedulingPlan) -> InputComparison { InputComparison(target: plan.input,status: "matchesInputs",basis: "Fixed lifecycle fixture") }
        func sourceStatus() -> DaemonSourceStatus { DaemonSourceStatus(availability) }
        func closeAdmission() { stopped = true }
        func shutdown() { stopped = true }
    }
    actor Builder: DaemonServicesBuilding {
        let availability: DaemonSourceReadiness
        var services: Services?
        init(availability: DaemonSourceReadiness = .ready) { self.availability = availability }
        func make(configuration: DaemonConfiguration,repository: any VerificationRepository,epoch: String,engineIdentity: String,resources: any WorkspaceResourceAdmitting) -> any DaemonWorkspaceServices {
            let value = Services(configuration: configuration,repository: repository,epoch: epoch,engine: engineIdentity,availability: availability)
            services = value; return value
        }
        func planID() async -> String? { await services?.planID }
    }
    func configuration(root: URL,explicitStart: Bool = true) throws -> DaemonConfiguration {
        let workspace = root.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace,withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700])
        return try DaemonConfiguration(workspace: workspace,executable: URL(fileURLWithPath: CommandLine.arguments[0]),stateDirectory: root.appendingPathComponent("state"),explicitStart: explicitStart)
    }
    func ready(_ admin: LocalDaemonAdministration) async throws -> DaemonStatus {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            do {
                let status = try await admin.status()
                if status.state != "recovering" { return status }
            } catch let error as InvarError where ["DAEMON_UNAVAILABLE","AUTHENTICATION_REQUIRED"].contains(error.code) {}
            try await Task.sleep(for: .milliseconds(10))
        }
        throw InvarError("TEST_DEADLINE","Host did not open its control plane")
    }
    @Test(arguments: 0..<8) func realHostOwnsStoreAndSharedServicesUntilExplicitStop(_ repetition: Int) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-host-" + UUID().uuidString)
        let configuration = try configuration(root: root), builder = Builder()
        let host = WorkspaceDaemon(servicesBuilder: builder,backend: StaticBackend(evaluator: ArchitectureRuleEvaluator()))
        let task = Task { try await host.serve(configuration) }
        defer { task.cancel(); do { try await task.value } catch is CancellationError {} catch { Issue.record(error) } }
        let admin = LocalDaemonAdministration(paths: configuration.paths)
        let initial = try await ready(admin)
        #expect(["ready","recovering"].contains(initial.state) && initial.activeOperations == 0)
        let secondConfiguration = try DaemonConfiguration(workspace: configuration.workspace,executable: configuration.executable,stateDirectory: root.appendingPathComponent("other-state"))
        let second = WorkspaceDaemon(servicesBuilder: Builder())
        await #expect(throws: InvarError.self) { try await second.serve(secondConfiguration) }
        #expect(!FileManager.default.fileExists(atPath: secondConfiguration.paths.stateDirectory.path))
        let planID = try #require(await builder.planID())
        let endpoint = try await admin.endpoint()
        let client = try await LocalVerificationClient.connect(endpoint: endpoint)
        let operation = WorkspaceOperation.verify(planID: planID,changeRevisionID: nil,replayOfRunID: nil)
        let prepared = try await client.prepare(operation,key: "host-verification",timeout: 20)
        let receipt = try await client.accept(prepared)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var runID: String?
        while ContinuousClock.now < deadline {
            let demand = try await client.operation(receipt.operationID)
            if demand.state == "completed" { runID = demand.resultID; break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let id = try #require(runID), result = try await client.run(id)
        #expect(result.acceptedAtCompletion)
        await client.shutdown()
        #expect(try await admin.status().state == "ready")
        let stopping = try await admin.stop(mode: .drain,deadlineSeconds: 2)
        #expect(stopping.state == "draining")
        try await task.value
        #expect(FileManager.default.fileExists(atPath: configuration.paths.stopLatch.path))
        #expect(!FileManager.default.fileExists(atPath: configuration.paths.controlSocket.path))
        #expect(!FileManager.default.fileExists(atPath: configuration.paths.hostControlRecord.path))
        let automatic = WorkspaceDaemon(servicesBuilder: Builder())
        let autoConfiguration = try self.configuration(root: root,explicitStart: false)
        await #expect(throws: InvarError.self) { try await automatic.serve(autoConfiguration) }
        let newOwner = try DaemonOwnership(paths: configuration.paths); try await newOwner.release()
        await admin.shutdown()
        try FileManager.default.removeItem(at: root); try FileManager.default.removeItem(at: configuration.paths.runtimeDirectory)
    }
    @Test func controlRemainsAvailableOfflineAndTaskCancellationDrainsOwnership() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-offline-" + UUID().uuidString)
        let configuration = try configuration(root: root), builder = Builder(availability: .sourceOffline)
        let host = WorkspaceDaemon(servicesBuilder: builder)
        let task = Task { try await host.serve(configuration) }
        let admin = LocalDaemonAdministration(paths: configuration.paths)
        defer { task.cancel(); do { try await task.value } catch is CancellationError {} catch { Issue.record(error) }; await admin.shutdown() }
        let initial = try await ready(admin)
        #expect(["sourceOffline","recovering"].contains(initial.state))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let owner = try DaemonOwnership(paths: configuration.paths); try await owner.release()
        #expect(await builder.services?.stopped == true)
        try FileManager.default.removeItem(at: root); try FileManager.default.removeItem(at: configuration.paths.runtimeDirectory)
    }
}

extension DaemonLifecycleTests {
    actor BlockingServices: DaemonWorkspaceServices {
        var entered = false, cancelled = false
        func start() async throws -> DaemonSourceStatus {
            entered = true
            do { try await Task.sleep(for: .seconds(30)); return DaemonSourceStatus(.ready) }
            catch { cancelled = true; throw error }
        }
        func sourceStatus() -> DaemonSourceStatus { DaemonSourceStatus(.sourceOffline) }
        func execute(_ demand: RunDemand) throws -> String { throw InvarError("UNSUPPORTED_OPERATION","Startup gate fixture") }
        func applicability(of plan: SchedulingPlan) -> InputComparison { InputComparison(target: nil,status: "unknown",basis: "Startup gate fixture") }
        func closeAdmission() {}
        func shutdown() {}
    }
    struct BlockingBuilder: DaemonServicesBuilding {
        let services: BlockingServices
        func make(configuration: DaemonConfiguration,repository: any VerificationRepository,epoch: String,engineIdentity: String,resources: any WorkspaceResourceAdmitting) -> any DaemonWorkspaceServices { services }
    }
    @Test func stopDuringSourceStartupCancelsInitializationBeforeTheStopDeadline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-startup-stop-" + UUID().uuidString)
        let configuration = try configuration(root: root), services = BlockingServices()
        let host = WorkspaceDaemon(servicesBuilder: BlockingBuilder(services: services))
        let task = Task { try await host.serve(configuration) }
        defer { task.cancel(); do { try await task.value } catch is CancellationError {} catch { Issue.record(error) } }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await services.entered) {
            guard ContinuousClock.now < deadline else { throw InvarError("TEST_DEADLINE","Host did not enter startup") }
            try await Task.sleep(for: .milliseconds(5))
        }
        let admin = LocalDaemonAdministration(paths: configuration.paths)
        #expect(try await admin.status().state == "recovering")
        let began = ContinuousClock.now
        _ = try await admin.stop(mode: .cancel,deadlineSeconds: 1)
        try await task.value
        #expect(began.duration(to: .now) < .seconds(1))
        #expect(await services.cancelled)
        await admin.shutdown()
        try FileManager.default.removeItem(at: root); try FileManager.default.removeItem(at: configuration.paths.runtimeDirectory)
    }
}

extension DaemonLifecycleTests {
    struct FailedServices: DaemonWorkspaceServices {
        func start() throws -> DaemonSourceStatus { throw InvarError("FIXTURE_RECOVERY_FAILURE","Initialization cannot establish its required state") }
        func sourceStatus() -> DaemonSourceStatus { DaemonSourceStatus(.sourceOffline) }
        func execute(_ demand: RunDemand) throws -> String { throw InvarError("UNSUPPORTED_OPERATION","Blocked recovery fixture") }
        func applicability(of plan: SchedulingPlan) -> InputComparison { InputComparison(target: nil,status: "unknown",basis: "Blocked recovery fixture") }
        func closeAdmission() {}
        func shutdown() {}
    }
    struct FailedBuilder: DaemonServicesBuilding {
        func make(configuration: DaemonConfiguration,repository: any VerificationRepository,epoch: String,engineIdentity: String,resources: any WorkspaceResourceAdmitting) -> any DaemonWorkspaceServices { FailedServices() }
    }
    @Test func blockedRecoveryKeepsLocalControlAvailableUntilExplicitStop() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-recovery-blocked-" + UUID().uuidString)
        let configuration = try configuration(root: root)
        let host = WorkspaceDaemon(servicesBuilder: FailedBuilder())
        let task = Task { try await host.serve(configuration) }
        defer { task.cancel(); do { try await task.value } catch is CancellationError {} catch { Issue.record(error) } }
        let admin = LocalDaemonAdministration(paths: configuration.paths)
        let status = try await ready(admin)
        #expect(status.state == "recoveryBlocked")
        #expect(status.diagnostics.contains { $0.contains("FIXTURE_RECOVERY_FAILURE") })
        _ = try await admin.stop(mode: .cancel,deadlineSeconds: 1)
        try await task.value
        await admin.shutdown()
        try FileManager.default.removeItem(at: root); try FileManager.default.removeItem(at: configuration.paths.runtimeDirectory)
    }
    @Test func privateAdministrationRejectsMutatedKernelIdentityAndUnsafeRecordMode() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-admin-peer-" + UUID().uuidString)
        let configuration = try configuration(root: root)
        let host = WorkspaceDaemon(servicesBuilder: Builder())
        let task = Task { try await host.serve(configuration) }
        defer { task.cancel(); do { try await task.value } catch is CancellationError {} catch { Issue.record(error) } }
        let admin = LocalDaemonAdministration(paths: configuration.paths)
        _ = try await ready(admin)
        let path = configuration.paths.hostControlRecord, original = try Data(contentsOf: path)
        let fields = try #require(JSONSerialization.jsonObject(with: original) as? [String:Any])
        for field in ["processID","startSeconds","auditIdentity"] {
            var changed = fields
            if field == "auditIdentity" { changed[field] = Data(repeating: 0,count: 32).base64EncodedString() }
            else { let number = try #require(fields[field] as? NSNumber); changed[field] = number.uint64Value+1 }
            let bytes = try JSONSerialization.data(withJSONObject: changed)
            try bytes.write(to: path,options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600],ofItemAtPath: path.path)
            await #expect(throws: InvarError.self) { try await admin.status() }
            try original.write(to: path,options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600],ofItemAtPath: path.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o644],ofItemAtPath: path.path)
        await #expect(throws: InvarError.self) { try await admin.status() }
        try FileManager.default.setAttributes([.posixPermissions: 0o600],ofItemAtPath: path.path)
        #expect(try await admin.status().state == "ready")
        _ = try await admin.stop(mode: .cancel,deadlineSeconds: 1)
        try await task.value; await admin.shutdown()
        try FileManager.default.removeItem(at: root); try FileManager.default.removeItem(at: configuration.paths.runtimeDirectory)
    }
}
