import ArchitectureClient
import ArchitectureCore
import ArchitectureExtensions
import Foundation
import Testing
import VerificationBackends
import VerificationCore
import VerificationDaemon
import VerificationDiscovery
import VerificationRuntime
import VerificationStore

@Suite(.timeLimit(.minutes(1))) struct ProviderActionTests {
    actor Starts: ExternalAdmissionAuthorizing {
        private var permit: ExternalAdmission?
        init(_ permit: ExternalAdmission) { self.permit = permit }
        func takeStart(_ id: String) throws -> ExternalAdmission {
            guard let value = permit, value.actionID == id else { throw InvarError("ACTION_OUTCOME_UNKNOWN","No live permit") }
            permit = nil; return value
        }
    }
    func intent(_ id: String = UUID().uuidString) throws -> ActionIntent {
        try ActionIntent(requestID: id,registrationID: "registration",sessionID: "source-session",providerID: "invar",actionID: "verify",actionDefinitionDigest: String(repeating: "1",count: 64),inputSchemaID: "invar.verify/2",effect: "externalExecution",binding: ExtensionBinding(workspaceID: "workspace",snapshotID: "snapshot",inputManifestDigest: String(repeating: "2",count: 64)),arguments: .object(["planID":.string("plan")]),requestedAt: Date().timeIntervalSince1970+0.001,deadline: Date().timeIntervalSince1970+60,idempotencyKey: id)
    }
    @Test func concreteSDKLedgerDuplicateReopenAndMissingLookupNeverPermitAnotherStart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-sdk-ledger-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        let path = root.appendingPathComponent("actions.json"), ledger = try ProviderActionLedger(path: path)
        let action = try intent(), first = try await ledger.reserve(action,providerID: "invar")
        #expect(first.mayStart && first.receipt.accepted && first.receipt.jobID != nil)
        let duplicate = try await ledger.reserve(action,providerID: "invar")
        #expect(!duplicate.mayStart && duplicate.receipt == first.receipt)
        await #expect(throws: ArchitectureError.self) { try await ledger.lookup(try intent(),providerID: "invar") }
        await ledger.shutdown()
        let reopened = try ProviderActionLedger(path: path)
        let recovered = try await reopened.reserve(action,providerID: "invar")
        #expect(!recovered.mayStart && recovered.receipt == first.receipt)
        #expect(try await reopened.lookup(action,providerID: "invar") == first.receipt)
        await reopened.shutdown(); try FileManager.default.removeItem(at: root)
    }
    func preflight(_ fixture: PublicationTests.Fixture,jobID: String,node: VerificationNode? = nil) async throws -> (ProviderActionRegistration,OperationReceipt) {
        let now = Date().timeIntervalSince1970, id = UUID().uuidString
        let operation = WorkspaceOperation.verify(planID: fixture.plan.id,changeRevisionID: nil,replayOfRunID: nil,node: node)
        let envelope = RequestEnvelope(id: UUID().uuidString,requestKey: id,principal: "agent",workspaceID: fixture.plan.body.input.workspaceID,fingerprint: try Canonical.identity(operation),operation: operation.name,daemonEpoch: fixture.epoch,expiresAt: now+60,retainUntil: now+120)
        _ = try await fixture.store.issueEnvelope(envelope,now: now)
        let base = ProviderActionRegistration(id: id,envelope: envelope,operation: operation,input: fixture.plan.body.input,sourceFingerprint: String(repeating: "1",count: 64),intent: Data(),runRequestID: id,run: Data(),expiresAt: now+120)
        try await fixture.store.createProviderAction(base)
        try await fixture.store.saveProviderActionState(ProviderActionState(id: id).revising(state: "accepted",jobID: jobID),expectedRevision: 1)
        return (base,OperationReceipt(id: envelope.id,operationID: jobID,fingerprint: envelope.fingerprint,acceptedAt: now,daemonEpoch: fixture.epoch))
    }
    @Test func liveAdmissionCommitsSDKJobMappingBeforeExecutionAndConsumesPermitOnlyOnce() async throws {
        let fixture = try await PublicationTests().fixture(), job = UUID().uuidString
        let (base,receipt) = try await preflight(fixture,jobID: job)
        let starts = Starts(ExternalAdmission(actionID: base.id,receipt: receipt))
        let scheduler = VerificationScheduler(backend: StaticBackend(evaluator: ArchitectureRuleEvaluator()),repository: fixture.store,resources: fixture.resources)
        let coordinator = WorkspaceCoordinator(repository: fixture.store,scheduler: scheduler,operations: DurableCoordinatorTests.Operations(),epoch: fixture.epoch,maximumDemands: 4,external: starts)
        defer { do { try await coordinator.shutdown(); try await PublicationTests().cleanup(fixture) } catch { Issue.record(error) } }
        #expect(try await coordinator.submitExternal(actionID: base.id) == receipt)
        #expect(try await fixture.store.loadReceipt(base.envelope.id) == receipt)
        #expect(try await fixture.store.providerActionForDemand(job) == base)
        #expect(try await fixture.store.providerActionState(base.id).state == "mapped")
        let complete = try await DurableCoordinatorTests().wait(job,coordinator: coordinator)
        #expect(complete.state == "completed" && complete.origin == "provider" && complete.id == job)
        await #expect(throws: InvarError.self) { try await coordinator.submitExternal(actionID: base.id) }
        #expect(try await fixture.store.loadDemand(job) == complete)
    }
    @Test func acceptedLedgerGapCannotBeConvertedIntoRunnableMapping() async throws {
        let fixture = try await PublicationTests().fixture(), job = UUID().uuidString
        defer { do { try await PublicationTests().cleanup(fixture) } catch { Issue.record(error) } }
        let (base,receipt) = try await preflight(fixture,jobID: job)
        let accepted = try await fixture.store.providerActionState(base.id)
        try await fixture.store.saveProviderActionState(accepted.revising(state: "outcomeUnknown",failure: InvarError("ACTION_OUTCOME_UNKNOWN","Process ended before live admission")),expectedRevision: accepted.revision)
        let demand = RunDemand(id: job,envelopeID: base.envelope.id,principal: base.envelope.principal,origin: "provider",request: base.operation,planID: fixture.plan.id,changeRevisionID: nil,state: "queued",revision: 1,executionIDs: [],resultID: nil,failure: nil)
        await #expect(throws: InvarError.self) { try await fixture.store.acceptExternalDemand(receipt,demand: demand,actionID: base.id) }
        #expect(try await fixture.store.loadReceipt(base.envelope.id) == nil)
        #expect(try await fixture.store.providerActionState(base.id).state == "outcomeUnknown")
        await #expect(throws: InvarError.self) { try await fixture.store.loadDemand(job) }
    }
    @Test func nodeAdmissionRejectsAnAbsentEntityAndAnotherSnapshot() async throws {
        let fixture = try await PublicationTests().fixture()
        defer { do { try await PublicationTests().cleanup(fixture) } catch { Issue.record(error) } }
        for snapshot in [fixture.plan.body.input.snapshotID,"other-snapshot"] {
            let selected = VerificationNode(snapshotID: snapshot,entityID: "absent")
            await #expect(throws: InvarError.self) { try await preflight(fixture,jobID: UUID().uuidString,node: selected) }
        }
        #expect(try await fixture.store.providerActionIDs().isEmpty)
    }
    @Test func registeredActionSchemasRequireConfirmationAndContainNoPermissionOrPathSwitches() throws {
        let manifest = InvarProviderManifest.value
        _ = try ExtensionRules.manifest(try JSONValue.encode(manifest))
        #expect(manifest.actions.count == 4 && manifest.actions.allSatisfy(\.requiresConfirmation))
        let model = try #require(manifest.actions.first { $0.id == "verify-model" })
        #expect(model.inputSchemaID == "invar.verify-model.v2")
        try ExtensionRules.schema(model.inputSchema,value: .object([:]))
        #expect(throws: ArchitectureError.self) { try ExtensionRules.schema(model.inputSchema,value: .object(["source":.string("/tmp/arbitrary.swift")])) }
        try ExtensionRules.schema(model.inputSchema,value: .object(["specification":.string("Verification/Selected/properties.json")]))
        #expect(throws: ArchitectureError.self) { try ExtensionRules.schema(model.inputSchema,value: .object(["planID":.string("unrelated")])) }
        let project = try #require(manifest.actions.first { $0.id == "verify-project" })
        try ExtensionRules.schema(project.inputSchema,value: .object(["configuration":.string("Verification/Project/invar.json")]))
        #expect(throws: ArchitectureError.self) { try ExtensionRules.schema(project.inputSchema,value: .object(["configuration":.string("config.json"),"allowExecution":.bool(true)])) }
        let verify = try #require(manifest.actions.first { $0.id == "verify" })
        try ExtensionRules.schema(verify.inputSchema,value: .object(["planID":.string("sealed")]))
        #expect(throws: ArchitectureError.self) { try ExtensionRules.schema(verify.inputSchema,value: .object(["planID":.string("sealed"),"allowExecution":.bool(true)])) }
    }
}
