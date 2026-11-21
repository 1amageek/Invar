import ArchitectureClient
import ArchitectureCore
import ArchitectureExtensions
import Foundation
import Testing
import VerificationBackends
import VerificationCore
import VerificationExplorer
import VerificationDiscovery
import VerificationRuntime
import VerificationStore

@Suite(.timeLimit(.minutes(1))) struct PublicationTests {
    actor Transport: ArchitectureExtensionProviding, OriginalPublicationChecking {
        private var runs: [String:ExtensionRun] = [:]
        private var contributions: [String:[ExtensionContribution]] = [:]
        private var manifests: [String:PublicationManifest] = [:]
        var offline = false
        var loseCommitACK = false
        var generation = 0
        var starts = 0
        var session = "one"
        var head = 0
        func configure(offline: Bool = false,loseCommitACK: Bool = false,session: String = "one") { self.offline = offline; self.loseCommitACK = loseCommitACK; self.session = session }
        func forgetRuns() { runs.removeAll() }
        func requireOriginalRun(_ run: ExtensionRun) throws {
            if offline { throw InvarError("SOURCE_OFFLINE","Injected transport outage") }
            guard let original = runs[run.id] else { throw InvarError("ORIGINAL_RUN_LOST","Original run lost") }
            guard original.slot == run.slot, original.generation == run.generation else { throw InvarError("IDEMPOTENCY_CONFLICT","Original reservation changed") }
        }
        func heartbeat() throws {}
        func inputManifest(snapshotID: String) throws -> InputManifest { throw InvarError("TEST_UNSUPPORTED","No source reads in this transport fixture") }
        private func replace(_ run: ExtensionRun,committed: Bool,completion: String) throws -> ExtensionRun {
            var value = try JSONValue.encode(run).object
            value["committed"] = .bool(committed); value["completion"] = .string(completion); value["sessionID"] = .string(session); value["publicationID"] = .string(session + run.id)
            return try JSONValue.object(value).decode(ExtensionRun.self)
        }
        func begin(runID: String,scope: String,contributionSetID: String,binding: ExtensionBinding,kinds: [String],viewIDs: [String]) throws -> ExtensionRun {
            if offline { throw InvarError("SOURCE_OFFLINE","Injected transport outage",exitCode: 6) }
            if let old = runs[runID] {
                let next = try replace(old,committed: old.committed,completion: old.completion)
                if old.sessionID != session { manifests[runID] = nil; contributions[runID] = nil }
                runs[runID] = next; return next
            }
            starts += 1; generation += 1
            let value: JSONValue = .object(["id":.string(runID),"providerID":.string("invar"),"registrationID":.string("registration"),"slot":.string(scope),"binding":try JSONValue.encode(binding),"generation":.number(Double(generation)),"contributionKinds":.array(kinds.map(JSONValue.string)),"viewIDs":.array([]),"publicationID":.string(session+runID),"sessionID":.string(session),"expiresAt":.number(Date().timeIntervalSince1970+60),"committed":.bool(false),"completion":.string("pending")])
            let run = try value.decode(ExtensionRun.self); runs[runID] = run; return run
        }
        func prepare(_ run: ExtensionRun,manifest: PublicationManifest) throws { manifests[run.id] = manifest }
        func stage(_ run: ExtensionRun,contributions: [ExtensionContribution]) throws { self.contributions[run.id] = contributions }
        func commit(_ run: ExtensionRun,manifest: PublicationManifest,completion: String) throws {
            guard try PublicationManifest(contributions: contributions[run.id] ?? []).entries == manifest.entries, manifests[run.id] == manifest else { throw InvarError("TEST_MANIFEST","Incomplete staging") }
            if head > run.generation { throw InvarError("PUBLICATION_SUPERSEDED","Newer head owns the slot") }
            runs[run.id] = try replace(run,committed: completion == "complete",completion: completion)
            if completion == "complete" { head = run.generation }
            if loseCommitACK { loseCommitACK = false; throw InvarError("CONNECTION_LOST","Commit was applied but ACK was lost") }
        }
        func nextAction() -> ActionIntent? { nil }
        func receipt(for intent: ActionIntent,receipt: ActionReceipt) throws {}
    }
    actor DelayedPublication: VerificationPublishing {
        let publisher: ExplorerPublisher
        var first: String?
        var waiting = false
        var released = false
        init(_ publisher: ExplorerPublisher) { self.publisher = publisher }
        func reserve(demand: RunDemand,plan: SchedulingPlan) async throws {
            if first == nil { first = demand.id }
            try await publisher.reserve(demand: demand,plan: plan)
        }
        func prepare(demand: RunDemand,run: VerificationRun,view: ChangeVerificationView) async throws -> PublicationRecord {
            if demand.id == first {
                waiting = true
                while !released { try await Task.sleep(for: .milliseconds(2)) }
            }
            return try await publisher.prepare(demand: demand,run: run,view: view)
        }
        func abandon(demandID: String,failure: InvarError) async throws { try await publisher.abandon(demandID: demandID,failure: failure) }
        func release() { released = true }
    }

    struct Fixture {
        let root: URL
        let store: SQLiteVerificationStore
        let plan: VerificationPlan
        let coordinator: WorkspaceCoordinator
        let publisher: ExplorerPublisher
        let resources: ResourcePool
        let transport: Transport
        let epoch: String
    }
    func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-publication-" + UUID().uuidString)
        let store = try SQLiteVerificationStore(root: root), original = DomainTests.inventory()
        let raw: JSONValue = .object(["schemaVersion":.string("1.0"),"workspaceID":.string(original.workspaceID),"snapshotID":.string(original.snapshotID),"scope":.array([.string(".")]),"files":.object([:]),"context":.object([:]),"contextDigest":.string(original.contextDigest),"dependencyStatus":.string("unknown"),"coverage":.array([])])
        let manifestBytes = try CanonicalJSON.encode(raw)
        let inventory = ScopeInventory(workspaceID: original.workspaceID,snapshotID: original.snapshotID,contextDigest: original.contextDigest,metadata: original.metadata,entities: original.entities,facts: original.facts,coverage: original.coverage,inputs: [],originalRecords: ["inputManifest":[manifestBytes]])
        let inputID = try await store.saveInput(CapturedWorkspace(inventory: inventory,files: [:]))
        let input = try await store.inputReference(inputID), jobs = [SchedulerTests.job("cycle")]
        let configuration = VerificationConfiguration(architecture: jobs.compactMap(\.policy)), digest = try configuration.identity()
        let body = PlanBody(input: input,executorIdentity: String(repeating: "0",count: 64),configurationDigest: digest,jobs: jobs,budget: RunBudget())
        let planID = try Canonical.identity(body), plan = VerificationPlan(id: planID,body: body)
        try await store.savePlan(plan)
        let epoch = UUID().uuidString
        try await store.activateEpoch(epoch,engineIdentity: body.executorIdentity)
        _ = try await store.observeInput(input,epoch: epoch)
        let transport = Transport(), resources = ResourcePool(policy: .development)
        let manifest = ExtensionManifest(extensionID: "invar",displayName: "Invar",requestedPermissions: [.graphRead,.graphsWrite,.runsWrite])
        let publisher = ExplorerPublisher(repository: store,manifest: manifest,resources: resources) { transport }
        let scheduler = VerificationScheduler(backend: StaticBackend(evaluator: ArchitectureRuleEvaluator()),repository: store,applicability: SchedulerTests.Current(value: "matchesInputs"),resources: resources)
        let coordinator = WorkspaceCoordinator(repository: store,scheduler: scheduler,authorization: DurableCoordinatorTests.Authorization(),operations: DurableCoordinatorTests.Operations(),epoch: epoch,maximumDemands: 8,publisher: publisher)
        return Fixture(root: root,store: store,plan: plan,coordinator: coordinator,publisher: publisher,resources: resources,transport: transport,epoch: epoch)
    }
    func execute(_ value: Fixture,key: String) async throws -> RunDemand {
        let (envelope,operation) = try await DurableCoordinatorTests().request(store: value.store,plan: value.plan,epoch: value.epoch,key: key)
        let receipt = try await value.coordinator.submit(envelope,operation: operation)
        return try await DurableCoordinatorTests().wait(receipt.operationID,coordinator: value.coordinator)
    }
    func cleanup(_ value: Fixture) async throws {
        try await value.coordinator.shutdown(); await value.publisher.shutdown(); try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root)
    }
    @Test func nodeReportIsBoundToItsSnapshotAndKeepsTheWorkspaceHead() async throws {
        let value = try await fixture()
        defer { do { try await cleanup(value) } catch { Issue.record(error) } }
        let workspace = try await execute(value,key: "workspace")
        try await value.publisher.flush()
        let input = value.plan.body.input
        for (snapshot,entity,valid) in [("other","a",false),(input.snapshotID,"missing",false),(input.snapshotID,"a",true)] {
            let operation = WorkspaceOperation.verify(planID: value.plan.id,changeRevisionID: nil,replayOfRunID: nil,
                node: VerificationNode(snapshotID: snapshot,entityID: entity))
            let envelope = try await ReassociationTests().envelope(operation,store: value.store,workspace: input.workspaceID,epoch: value.epoch)
            if !valid {
                await #expect(throws: InvarError.self) { try await value.coordinator.submit(envelope,operation: operation) }
                continue
            }
            let receipt = try await value.coordinator.submit(envelope,operation: operation)
            let demand = try await DurableCoordinatorTests().wait(receipt.operationID,coordinator: value.coordinator)
            try await value.publisher.flush()
            let record = try #require(try await value.store.loadPublication(demand.id))
            #expect(record.state == "committed")
            let payload = try #require(record.payload)
            let reports = try JSONDecoder().decode([ExtensionContribution].self,from: payload).filter { $0.kind == "annotation" }
            #expect(reports.count == 1)
            #expect(reports.first?.binding.entityIDs == [entity])
            #expect(reports.first?.binding.snapshotID == input.snapshotID)
            #expect(try await value.store.latestView(workspaceID: input.workspaceID) == workspace.view)
        }
    }

    @Test func sameInputReverseCompletionSelectsOnlyTheNewerPublishedGeneration() async throws {
        let value = try await fixture(), delayed = DelayedPublication(value.publisher)
        let scheduler = VerificationScheduler(backend: StaticBackend(evaluator: ArchitectureRuleEvaluator()),repository: value.store,applicability: SchedulerTests.Current(value: "matchesInputs"),resources: value.resources)
        let coordinator = WorkspaceCoordinator(repository: value.store,scheduler: scheduler,authorization: DurableCoordinatorTests.Authorization(),operations: DurableCoordinatorTests.Operations(),epoch: value.epoch,maximumDemands: 8,publisher: delayed)
        defer { do { try await coordinator.shutdown(); try await cleanup(value) } catch { Issue.record(error) } }
        let (firstEnvelope,operation) = try await DurableCoordinatorTests().request(store: value.store,plan: value.plan,epoch: value.epoch,key: "first-delayed")
        let firstReceipt = try await coordinator.submit(firstEnvelope,operation: operation)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await delayed.waiting) {
            guard ContinuousClock.now < deadline else { throw InvarError("TEST_DEADLINE","First demand did not reach delayed publication preparation") }
            try await Task.sleep(for: .milliseconds(2))
        }
        let (secondEnvelope,secondOperation) = try await DurableCoordinatorTests().request(store: value.store,plan: value.plan,epoch: value.epoch,key: "second")
        let secondReceipt = try await coordinator.submit(secondEnvelope,operation: secondOperation)
        let second = try await DurableCoordinatorTests().wait(secondReceipt.operationID,coordinator: coordinator)
        #expect(try await value.store.latestView(workspaceID: value.plan.body.input.workspaceID) == nil)
        try await value.publisher.flush()
        #expect(try await value.store.latestView(workspaceID: value.plan.body.input.workspaceID) == second.view)
        await delayed.release()
        let first = try await DurableCoordinatorTests().wait(firstReceipt.operationID,coordinator: coordinator)
        #expect(first.view!.sequence > second.view!.sequence)
        #expect(try await value.store.latestView(workspaceID: value.plan.body.input.workspaceID) == second.view)
        try await value.publisher.flush()
        #expect(try await value.store.loadPublication(first.id)?.state == "superseded")
        #expect(try await value.store.latestView(workspaceID: value.plan.body.input.workspaceID) == second.view)
        #expect(try await value.store.loadView(first.view!.id).runIDs == [first.resultID!])
        await value.publisher.shutdown()
        try await value.store.shutdown()
        let reopened = try SQLiteVerificationStore(root: value.root)
        #expect(try await reopened.latestView(workspaceID: value.plan.body.input.workspaceID) == second.view)
        try await reopened.shutdown()
    }

    @Test func publishedViewRetainsItsReferencedPlanRunAndEvidenceAfterOrdinaryRequestRetentionExpires() async throws {
        let value = try await fixture()
        defer { do { try await cleanup(value) } catch { Issue.record(error) } }
        let demand = try await execute(value,key: "retained-head")
        try await value.publisher.flush()
        let reference = try #require(demand.view), runID = try #require(demand.resultID)
        let before = try await value.store.loadRun(runID)
        _ = try await value.store.prune(now: Date().timeIntervalSince1970+StorePolicy.development.retentionSeconds+2,maximumObjects: 100)
        #expect(try await value.store.latestView(workspaceID: reference.workspaceID) == reference)
        #expect(try await value.store.loadRun(runID) == before)
        #expect(try await value.store.schedulingPlan(value.plan.id).id == value.plan.id)
        for evidence in before.attempts { #expect(try await value.store.loadEvidence(evidence.id) == evidence) }
    }

    @Test func lostOriginalRunCannotAllocateAReplacementGenerationDuringReconciliation() async throws {
        let value = try await fixture()
        defer { do { try await cleanup(value) } catch { Issue.record(error) } }
        let demand = try await execute(value,key: "original-lost")
        await value.transport.forgetRuns()
        try await value.publisher.flush()
        let record = try #require(try await value.store.loadPublication(demand.id))
        #expect(record.state == "blocked" && record.failure?.code == "ORIGINAL_RUN_LOST")
        #expect(await value.transport.starts == 1)
        #expect(try await value.store.latestView(workspaceID: value.plan.body.input.workspaceID) == nil)
        #expect(try await value.store.loadDemand(demand.id).state == "completed")
    }

    @Test func partialDeliveryCannotReplaceAnExistingCompletePublishedView() async throws {
        let value = try await fixture()
        defer { do { try await cleanup(value) } catch { Issue.record(error) } }
        let complete = try await execute(value,key: "complete")
        try await value.publisher.flush()
        let scheduler = VerificationScheduler(backend: SchedulerTests.ResourceFailure(),repository: value.store,resources: value.resources)
        let coordinator = WorkspaceCoordinator(repository: value.store,scheduler: scheduler,authorization: DurableCoordinatorTests.Authorization(),operations: DurableCoordinatorTests.Operations(),epoch: value.epoch,maximumDemands: 8,publisher: value.publisher)
        defer { do { try await coordinator.shutdown() } catch { Issue.record(error) } }
        let operation = WorkspaceOperation.verify(planID: value.plan.id,changeRevisionID: nil,replayOfRunID: complete.resultID)
        let envelope = try await ReassociationTests().envelope(operation,store: value.store,workspace: value.plan.body.input.workspaceID,epoch: value.epoch)
        let receipt = try await coordinator.submit(envelope,operation: operation)
        let partial = try await DurableCoordinatorTests().wait(receipt.operationID,coordinator: coordinator)
        #expect(partial.state == "completed" && partial.view != nil)
        let record = try #require(try await value.store.loadPublication(partial.id))
        #expect(record.completion == "partial")
        await #expect(throws: InvarError.self) { try await value.store.savePublication(record.revising(state: "committed"),expectedRevision: record.revision) }
        try await value.publisher.flush()
        #expect(try await value.store.loadPublication(partial.id)?.state == "delivered")
        #expect(try await value.store.latestView(workspaceID: value.plan.body.input.workspaceID) == complete.view)
        _ = try await value.store.invalidateSource(workspaceID: value.plan.body.input.workspaceID,epoch: value.epoch,reason: "Source changed after publication")
        #expect(try await value.store.latestView(workspaceID: value.plan.body.input.workspaceID) == complete.view)
    }

    @Test func lostCommitACKReconcilesOriginalGenerationAfterRestartWithoutChangingEvidenceOrPayload() async throws {
        let value = try await fixture(), demand = try await execute(value,key: "once")
        #expect(demand.state == "completed")
        let original = try #require(try await value.store.loadPublication(demand.id))
        #expect(original.state == "ready" && original.generation == 1)
        #expect(try await value.store.latestView(workspaceID: value.plan.body.input.workspaceID) == nil)
        let view = try #require(original.view)
        #expect(try await value.store.loadView(view.id).runIDs == [demand.resultID!])
        await value.transport.configure(loseCommitACK: true)
        try await value.publisher.flush()
        let lost = try #require(try await value.store.loadPublication(demand.id))
        #expect(lost.state == "ready" && lost.failure?.code == "CONNECTION_LOST")
        #expect(try await value.store.latestView(workspaceID: value.plan.body.input.workspaceID) == nil)
        await value.publisher.shutdown()
        let replacement = ExplorerPublisher(repository: value.store,manifest: ExtensionManifest(extensionID: "invar",displayName: "Invar",requestedPermissions: [.graphsWrite,.runsWrite]),resources: value.resources) { value.transport }
        await value.transport.configure(session: "two")
        try await replacement.flush()
        let delivered = try #require(try await value.store.loadPublication(demand.id))
        #expect(delivered.state == "committed" && delivered.generation == original.generation)
        #expect(delivered.payload == original.payload && delivered.view == original.view)
        #expect(try await value.store.latestView(workspaceID: value.plan.body.input.workspaceID) == delivered.view)
        #expect(await value.transport.starts == 1)
        #expect(try await value.store.loadDemand(demand.id) == demand)
        await replacement.shutdown(); try await cleanup(value)
    }
    @Test func lateOlderResultCannotAdvanceNewerHeadAndOfflineReservationDoesNotRewriteTruth() async throws {
        let value = try await fixture(), first = try await execute(value,key: "first"), second = try await execute(value,key: "second")
        // Deliver newer generation first, then retry the older immutable outbox.
        let older = try #require(try await value.store.loadPublication(first.id)), newer = try #require(try await value.store.loadPublication(second.id))
        #expect(older.generation == 1 && newer.generation == 2)
        // A separate host completion raises the authoritative slot generation.
        await value.transport.configure(offline: true)
        try await value.publisher.flush()
        #expect(try await value.store.loadPublication(first.id)?.state == "ready")
        let third = try await execute(value,key: "offline")
        #expect(third.state == "completed")
        #expect(try await value.store.loadPublication(third.id)?.state == "blocked")
        #expect(try await value.store.loadRun(third.resultID!).attempts.allSatisfy { $0.execution == "completed" })
        await value.transport.configure()
        // Force the host's newer complete head to exercise superseded delivery.
        await value.transport.setHead(2)
        try await value.publisher.flush()
        #expect(try await value.store.loadPublication(first.id)?.state == "superseded")
        #expect(try await value.store.loadPublication(second.id)?.state == "committed")
        #expect(try await value.store.loadDemand(first.id) == first)
        try await cleanup(value)
    }
}

extension PublicationTests.Transport {
    func setHead(_ generation: Int) { head = generation }
}
