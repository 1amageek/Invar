import Foundation
import Testing
import VerificationCore
@testable import VerificationStore

@Suite(.timeLimit(.minutes(1)))
struct StoreLedgerTests {
    func envelope(epoch: String,request: WorkspaceOperation,key: String = "request",id: String = UUID().uuidString,now: Double = 100) throws -> RequestEnvelope {
        let fingerprint = try Canonical.identity(request)
        return RequestEnvelope(id: id,requestKey: key,principal: "authenticated-fixture",workspaceID: "workspace",fingerprint: fingerprint,operation: request.name,daemonEpoch: epoch,expiresAt: now+30,retainUntil: now+60)
    }
    func demand(_ envelope: RequestEnvelope,request: WorkspaceOperation,plan: VerificationPlan,state: String = "queued",revision: Int = 1,result: String? = nil) -> RunDemand {
        RunDemand(id: Canonical.parts("demand",[envelope.id]),envelopeID: envelope.id,principal: envelope.principal,origin: "internal",request: request,planID: plan.id,changeRevisionID: nil,state: state,revision: revision,executionIDs: [],resultID: result,failure: nil)
    }
    @Test func duplicateRequestsKeepOneReceiptAndCannotExtendDeadlineOrChangeFingerprint() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let epoch = UUID().uuidString
        try await store.activateEpoch(epoch,engineIdentity: String(repeating: "1",count: 64))
        let operation = WorkspaceOperation.verify(planID: plan.id,changeRevisionID: nil,replayOfRunID: nil)
        let proposed = try envelope(epoch: epoch,request: operation)
        let fixed = try await store.issueEnvelope(proposed,now: 100)
        let value = demand(fixed,request: operation,plan: plan)
        let receipts = try await withThrowingTaskGroup(of: OperationReceipt.self) { group in
            for _ in 0..<20 { group.addTask { try await store.acceptDemand(fixed,demand: value,now: 101) } }
            var results: [OperationReceipt] = []
            for try await receipt in group { results.append(receipt) }; return results
        }
        #expect(receipts.count == 20 && receipts.allSatisfy { $0 == receipts.first })
        let pending = try await store.pendingDemands()
        #expect(pending.count == 1 && pending[0] == value)
        let retry = try envelope(epoch: epoch,request: operation,now: 110)
        let original = try await store.issueEnvelope(retry,now: 110)
        #expect(original == fixed && original.expiresAt == 130)
        await #expect(throws: InvarError.self) { try await store.acceptDemand(fixed,demand: value,now: 131) }
        let differentOperation = WorkspaceOperation.verify(planID: plan.id,changeRevisionID: nil,replayOfRunID: "different")
        let conflict = try envelope(epoch: epoch,request: differentOperation)
        await #expect(throws: InvarError.self) { try await store.issueEnvelope(conflict,now: 110) }
        let secondEpoch = UUID().uuidString
        try await store.activateEpoch(secondEpoch,engineIdentity: String(repeating: "1",count: 64))
        await #expect(throws: InvarError.self) { try await store.acceptDemand(fixed,demand: value,now: 110) }
        let retained = try await store.loadReceipt(fixed.id)
        #expect(retained == receipts[0])
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test func terminalRunEvidenceAssociationAndViewCommitOrRollbackTogether() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let epoch = UUID().uuidString
        try await store.activateEpoch(epoch,engineIdentity: String(repeating: "1",count: 64))
        let operation = WorkspaceOperation.verify(planID: plan.id,changeRevisionID: nil,replayOfRunID: nil)
        let proposed = try envelope(epoch: epoch,request: operation)
        let fixed = try await store.issueEnvelope(proposed,now: 100)
        _ = try await store.acceptDemand(fixed,demand: demand(fixed,request: operation,plan: plan),now: 101)
        try await store.transitionDemand(demand(fixed,request: operation,plan: plan,state: "running",revision: 2),expectedRevision: 1)
        let run = try ReplayTests.run("terminal",plan: plan.id,outcome: "holdsWithinScope")
        let terminal = demand(fixed,request: operation,plan: plan,state: "completed",revision: 3,result: run.id)
        func view(sequence: Int) -> ChangeVerificationView {
            ChangeVerificationView(workspaceID: plan.body.input.workspaceID,changeRevisionID: nil,input: plan.body.input,daemonEpoch: epoch,sequence: sequence,delta: nil,impactEntityIDs: [],unknownBoundaries: ["Fixture recorded graph only"],planIDs: [plan.id],runIDs: [run.id],evidenceIDs: run.attempts.map(\.id),associations: run.associations,pendingDemandIDs: [],diagnostics: [])
        }
        await #expect(throws: InvarError.self) { try await store.completeDemand(terminal,run: run,view: view(sequence: 8),expectedRevision: 2) }
        await #expect(throws: InvarError.self) { try await store.loadRun(run.id) }
        await #expect(throws: InvarError.self) { try await store.loadEvidence(run.attempts[0].id) }
        #expect(try await store.loadDemand(terminal.id).state == "running")
        let valid = view(sequence: 1), viewReference = try valid.reference()
        let reserving = PublicationRecord(id: terminal.id,providerID: "invar",input: plan.body.input,bindingDigest: String(repeating: "a",count: 64))
        try await store.savePublication(reserving,expectedRevision: 0)
        let reserved = reserving.revising(state: "reserved",slot: "fixture-slot",generation: 1,handle: Data("opaque adapter handle".utf8))
        try await store.savePublication(reserved,expectedRevision: 1)
        let changedGeneration = reserved.revising(state: "ready",generation: 2,view: viewReference,payload: Data("[]".utf8),completion: "complete")
        await #expect(throws: InvarError.self) { try await store.completeDemand(terminal,run: run,view: valid,publication: changedGeneration,expectedRevision: 2) }
        await #expect(throws: InvarError.self) { try await store.loadRun(run.id) }
        await #expect(throws: InvarError.self) { try await store.loadView(viewReference.id) }
        #expect(try await store.loadDemand(terminal.id).state == "running")
        #expect(try await store.loadPublication(terminal.id) == reserved)
        let ready = reserved.revising(state: "ready",view: viewReference,payload: Data("[]".utf8),completion: "complete")
        try await store.completeDemand(terminal,run: run,view: valid,publication: ready,expectedRevision: 2)
        #expect(try await store.loadPublication(terminal.id) == ready)
        let reference = try await store.latestView(workspaceID: plan.body.input.workspaceID)
        let expected = try valid.reference()
        #expect(reference == nil)
        #expect(try await store.loadView(expected.id) == valid)
        #expect(try await store.loadDemand(terminal.id).resultID == run.id)
        #expect(try await store.loadDemand(terminal.id).view == expected)
        try await store.shutdown()
        let reopened = try SQLiteVerificationStore(root: root)
        #expect(try await reopened.loadView(expected.id) == valid)
        #expect(try await reopened.loadRun(run.id) == run)
        #expect(try await reopened.loadPublication(terminal.id) == ready)
        try await reopened.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test func evidenceIdentityRejectsContentMutationAndAssociationsDoNotRewriteIt() throws {
        let evidence = try DomainTests.evidence("a")
        let bytes = try Canonical.encode(evidence)
        var encoded = try #require(JSONSerialization.jsonObject(with: bytes) as? [String:Any])
        encoded["outcome"] = "violatedWithinScope"
        let changed = try JSONSerialization.data(withJSONObject: encoded)
        #expect(throws: InvarError.self) { try JSONDecoder().decode(VerificationEvidence.self,from: changed) }
        let input = try VerificationInput.reference(DomainTests.inventory())
        let current = EvidenceAssociation.make(evidence: evidence,changeRevisionID: nil,input: input,status: "matchesInputs",basis: "fixed snapshot",unknownBoundaries: [],reuseDecision: "original")
        let stale = EvidenceAssociation.make(evidence: evidence,changeRevisionID: nil,input: input,status: "stale",basis: "later source event",unknownBoundaries: ["Target is unavailable"],reuseDecision: "historical")
        #expect(current.evidenceID == stale.evidenceID && current.id != stale.id)
        #expect(try Canonical.encode(evidence) == bytes)
    }
}

extension StoreLedgerTests {
    @Test func newSourceInvalidatesAssessmentHistoryAndLateCompletionStaysHistorical() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let epoch = UUID().uuidString
        try await store.activateEpoch(epoch,engineIdentity: String(repeating: "1",count: 64))
        let firstHead = try await store.observeInput(plan.body.input,epoch: epoch)
        let run = try ReplayTests.run("verified",plan: plan.id,outcome: "holdsWithinScope")
        try await store.saveRun(run)
        func view(input: VerificationInput,sourceRevision: Int,sequence: Int,associations: [EvidenceAssociation]) -> ChangeVerificationView {
            ChangeVerificationView(workspaceID: input.workspaceID,changeRevisionID: nil,input: input,daemonEpoch: epoch,sourceRevision: sourceRevision,sequence: sequence,delta: nil,impactEntityIDs: [],unknownBoundaries: [],planIDs: [plan.id],runIDs: [run.id],evidenceIDs: run.attempts.map(\.id),associations: associations,pendingDemandIDs: [],diagnostics: [])
        }
        _ = try await store.commitView(view(input: plan.body.input,sourceRevision: firstHead.revision,sequence: 2,associations: run.associations))
        let inventory = DomainTests.inventory(complete: false,snapshot: "new-source")
        _ = try await store.saveInput(CapturedWorkspace(inventory: inventory,files: [:]))
        let input = try VerificationInput.reference(inventory)
        let secondHead = try await store.observeInput(input,epoch: epoch)
        #expect(secondHead.revision == firstHead.revision + 1)
        let current = try #require(try await store.latestAssessment(workspaceID: input.workspaceID))
        let uncertain = try await store.loadView(current.id)
        #expect(uncertain.associations.first?.applicability == "unknown")
        #expect(uncertain.evidenceIDs == run.attempts.map(\.id))
        let late = view(input: plan.body.input,sourceRevision: firstHead.revision,sequence: 4,associations: run.associations)
        let lateReference = try await store.commitView(late)
        #expect(try await store.latestView(workspaceID: input.workspaceID) == nil)
        #expect(try await store.loadView(lateReference.id) == late)
        #expect(try await store.loadEvidence(run.attempts[0].id).outcome == "holdsWithinScope")
        let next = view(input: input,sourceRevision: secondHead.revision,sequence: 5,associations: uncertain.associations)
        let reference = try await store.commitView(next)
        #expect(try await store.latestAssessment(workspaceID: input.workspaceID) == reference)
        try await store.shutdown()
        let reopened = try SQLiteVerificationStore(root: root)
        #expect(try await reopened.latestAssessment(workspaceID: input.workspaceID) == reference)
        #expect(try await reopened.sourceHead(workspaceID: input.workspaceID) == secondHead)
        try await reopened.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension StoreLedgerTests {
    @Test func terminalStatusCannotBypassAtomicResultAndTypedRequestBinding() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let epoch = UUID().uuidString
        try await store.activateEpoch(epoch,engineIdentity: String(repeating: "1",count: 64))
        let request = WorkspaceOperation.verify(planID: plan.id,changeRevisionID: nil,replayOfRunID: nil)
        let fixed = try await store.issueEnvelope(envelope(epoch: epoch,request: request),now: 100)
        let forged = demand(fixed,request: .verify(planID: plan.id,changeRevisionID: nil,replayOfRunID: "changed"),plan: plan)
        await #expect(throws: InvarError.self) { try await store.acceptDemand(fixed,demand: forged,now: 101) }
        let queued = demand(fixed,request: request,plan: plan)
        _ = try await store.acceptDemand(fixed,demand: queued,now: 101)
        let running = queued.transitioning(to: "running")
        try await store.transitionDemand(running,expectedRevision: 1)
        let terminal = running.transitioning(to: "completed",resultID: "missing-run")
        await #expect(throws: InvarError.self) { try await store.transitionDemand(terminal,expectedRevision: 2) }
        await #expect(throws: InvarError.self) { try await store.completeDemand(terminal,run: nil,view: nil,expectedRevision: 2) }
        #expect(try await store.loadDemand(queued.id) == running)
        try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}

extension StoreLedgerTests {
    @Test func invalidationRecordsUnknownBeforeRecaptureAndRetainsOriginalEvidence() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        defer {
            do { try await store.shutdown(); try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
        }
        let epoch = UUID().uuidString
        try await store.activateEpoch(epoch,engineIdentity: plan.body.executorIdentity)
        let source = try await store.observeInput(plan.body.input,epoch: epoch)
        let run = try ReplayTests.run("source-fence",plan: plan.id,outcome: "holdsWithinScope")
        try await store.saveRun(run)
        func view(sequence: Int,fence: Int) -> ChangeVerificationView {
            ChangeVerificationView(workspaceID: plan.body.input.workspaceID,changeRevisionID: nil,input: plan.body.input,daemonEpoch: epoch,sourceRevision: fence,sequence: sequence,delta: nil,impactEntityIDs: [],unknownBoundaries: [],planIDs: [plan.id],runIDs: [run.id],evidenceIDs: run.attempts.map(\.id),associations: run.associations,pendingDemandIDs: [],diagnostics: [])
        }
        let knownSequence = try await store.nextViewSequence(workspaceID: plan.body.input.workspaceID)
        let known = try await store.commitView(view(sequence: knownSequence,fence: source.revision))
        #expect(try await store.latestAssessment(workspaceID: plan.body.input.workspaceID) == known)
        let invalid = try #require(try await store.invalidateSource(workspaceID: plan.body.input.workspaceID,epoch: epoch,reason: "Source event requires resync"))
        #expect(!invalid.confirmed && invalid.input == plan.body.input && invalid.revision == source.revision+1)
        let uncertain = try #require(try await store.latestAssessment(workspaceID: plan.body.input.workspaceID))
        #expect(try await store.loadView(uncertain.id).associations.allSatisfy { $0.applicability == "unknown" })
        #expect(try await store.loadEvidence(run.attempts[0].id) == run.attempts[0])
        for fence in [source.revision,invalid.revision] {
            let sequence = try await store.nextViewSequence(workspaceID: plan.body.input.workspaceID)
            _ = try await store.commitView(view(sequence: sequence,fence: fence))
            #expect(try await store.latestView(workspaceID: plan.body.input.workspaceID) == nil)
        }
        #expect(try await store.invalidateSource(workspaceID: plan.body.input.workspaceID,epoch: epoch,reason: "Source event requires resync") == invalid)
        let confirmed = try await store.observeInput(plan.body.input,epoch: epoch)
        #expect(confirmed.confirmed && confirmed.revision == invalid.revision+1 && confirmed.input == invalid.input)
        await #expect(throws: InvarError.self) { try await store.invalidateSource(workspaceID: plan.body.input.workspaceID,epoch: "other-epoch",reason: "Invalid") }
        #expect(try await store.loadRun(run.id) == run)
    }
}
