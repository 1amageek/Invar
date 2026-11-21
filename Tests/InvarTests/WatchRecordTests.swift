import ArchitectureCore
import Foundation
import Testing
import VerificationCore
import VerificationDaemon
import VerificationStore

@Suite(.timeLimit(.minutes(1))) struct WatchRecordTests {
    struct Fixture {
        let store: SQLiteVerificationStore
        let root: URL
        let plan: VerificationPlan
        let epoch: String
        let authority: DaemonSessionAuthority
        let grant: ClientSessionGrant
        let record: WatchRecord
    }
    func accepted(_ request: WorkspaceOperation,store: SQLiteVerificationStore,grant: ClientSessionGrant,epoch: String,key: String) async throws -> RunDemand {
        let now = Date().timeIntervalSince1970, fingerprint = try Canonical.identity(request)
        let envelope = RequestEnvelope(id: UUID().uuidString,sessionID: grant.session.id,capabilities: grant.session.grants.compactMap(WorkspaceCapability.init(rawValue:)),requestKey: key,principal: grant.session.principal,workspaceID: grant.workspaceID,fingerprint: fingerprint,operation: request.name,daemonEpoch: epoch,policyRevision: grant.session.policyRevision,expiresAt: now+15,retainUntil: now+60)
        let issued = try await store.issueEnvelope(envelope,now: now)
        let demand = RunDemand(id: Canonical.parts("invar.operation/2",[issued.id]),envelopeID: issued.id,principal: issued.principal,origin: "internal",request: request,planID: nil,changeRevisionID: nil,state: "queued",revision: 1,executionIDs: [],resultID: nil,failure: nil)
        _ = try await store.acceptDemand(issued,demand: demand,now: now)
        let running = demand.transitioning(to: "running")
        try await store.transitionDemand(running,expectedRevision: 1)
        return running
    }
    func fixture(shortSession: Bool = false) async throws -> Fixture {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let peer = try ConnectionPeer.current(), epoch = UUID().uuidString
        let capabilities: Set<WorkspaceCapability> = [.read,.planning,.verification,.watching]
        let base = DaemonAuthorityTests().policy(plan: plan,peer: peer,capabilities: capabilities)
        let policy = WorkspacePolicy(workspaceID: base.workspaceID,engineIdentity: base.engineIdentity,revision: base.revision,peers: base.peers,approvals: base.approvals,sessionSeconds: shortSession ? 2 : base.sessionSeconds,principalSeconds: base.principalSeconds,maximumSessions: base.maximumSessions,maximumConnections: base.maximumConnections,maximumEnvelopeSeconds: base.maximumEnvelopeSeconds)
        try await store.savePolicy(policy,expectedRevision: 0)
        try await store.activateEpoch(epoch,engineIdentity: plan.body.executorIdentity)
        let authority = DaemonSessionAuthority(repository: store,epoch: epoch)
        let grant = try await authority.open(peer: peer,label: "watch-fixture",requested: capabilities)
        let demand = try await accepted(.watch(configurationPath: "contracts.json",budget: RunBudget()),store: store,grant: grant,epoch: epoch,key: "watch")
        let principal = try #require(try await store.principal(identity: grant.session.principal))
        let record = WatchRecord(id: demand.id,envelopeID: demand.envelopeID,workspaceID: grant.workspaceID,principal: principal.principal,policyRevision: policy.revision,capabilities: principal.capabilities,configurationPath: "contracts.json",budget: RunBudget(),expiresAt: principal.expiresAt)
        return Fixture(store: store,root: root,plan: plan,epoch: epoch,authority: authority,grant: grant,record: record)
    }
    func register(_ value: Fixture) async throws -> WatchRecord {
        try await value.store.createWatch(value.record)
        let parent = try await value.store.loadDemand(value.record.id)
        let terminal = parent.transitioning(to: "completed",resultID: value.record.id)
        try await value.store.completeDemand(terminal,run: nil,view: nil,expectedRevision: parent.revision)
        return try await value.store.loadWatch(value.record.id)
    }
    @Test func originalAuthorityAndCycleReferencesSurviveReopenButCannotBeExtendedOrForged() async throws {
        let value = try await fixture()
        let record = try await register(value)
        let demand = try await accepted(.preparePlan(configurationPath: "contracts.json",changeRevisionID: nil,budget: value.record.budget),store: value.store,grant: value.grant,epoch: value.epoch,key: "prepare")
        let preparing = record.revising(state: "active",cycle: WatchCycle(generation: 1,phase: "preparing",pendingDemandID: demand.id))
        try await value.store.saveWatch(preparing,expectedRevision: record.revision)
        let forged = WatchRecord(id: preparing.id,envelopeID: preparing.envelopeID,workspaceID: preparing.workspaceID,principal: preparing.principal,policyRevision: preparing.policyRevision,capabilities: preparing.capabilities+[.nativeExecution],configurationPath: preparing.configurationPath,budget: preparing.budget,expiresAt: preparing.expiresAt+1,revision: preparing.revision+1,state: "active",cycle: preparing.cycle)
        await #expect(throws: InvarError.self) { try await value.store.saveWatch(forged,expectedRevision: preparing.revision) }
        #expect(try await value.store.loadWatch(preparing.id) == preparing)
        await value.authority.shutdown(); try await value.store.shutdown()
        let reopened = try SQLiteVerificationStore(root: value.root)
        #expect(try await reopened.loadWatch(preparing.id) == preparing)
        let paused = preparing.revising(state: "paused",failure: InvarError("TEST_PAUSE","Explicit test pause"))
        try await reopened.saveWatch(paused,expectedRevision: preparing.revision)
        let stopping = paused.revising(state: "stopping",stopTarget: "stopped")
        try await reopened.saveWatch(stopping,expectedRevision: paused.revision)
        let stopped = stopping.revising(state: "stopped",cycle: WatchCycle(generation: 1,phase: "idle"))
        await #expect(throws: InvarError.self) { try await reopened.saveWatch(stopped,expectedRevision: stopping.revision) }
        #expect(try await reopened.loadWatch(stopping.id) == stopping)
        _ = try await reopened.finishDemandFailure(demand.id,failure: InvarError("CANCELLED","Fixture child has no physical worker"),cancelled: true)
        try await reopened.saveWatch(stopped,expectedRevision: stopping.revision)
        await #expect(throws: InvarError.self) { try await reopened.saveWatch(stopped.revising(state: "active"),expectedRevision: stopped.revision) }
        #expect(try await reopened.watches(states: ["active","paused"]).isEmpty)
        try await reopened.shutdown(); try FileManager.default.removeItem(at: value.root)
    }
    @Test func revocationBlocksFreshWorkWithoutRemovingHistoricalWatchOrCleanupAuthority() async throws {
        let value = try await fixture()
        let record = try await register(value)
        let peer = try ConnectionPeer.current(), revoked = DaemonAuthorityTests().policy(plan: value.plan,peer: peer,revision: 2,capabilities: [.read])
        try await value.store.savePolicy(revoked,expectedRevision: 1)
        let next = record.revising(state: "active",cycle: WatchCycle(generation: 1,phase: "preparing"))
        await #expect(throws: InvarError.self) { try await value.store.saveWatch(next,expectedRevision: record.revision) }
        let stopped = record.revising(state: "stopped")
        try await value.store.saveWatch(stopped,expectedRevision: record.revision)
        #expect(try await value.store.loadWatch(stopped.id).state == "stopped")
        await value.authority.shutdown(); try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root)
    }
    @Test func derivedWatchRequestSurvivesAgentSessionExpiryWithoutWideningAuthorityOrDeadline() async throws {
        let value = try await fixture(shortSession: true)
        defer {
            await value.authority.shutdown()
            do { try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root) } catch { Issue.record(error) }
        }
        let record = try await register(value)
        let preparing = record.revising(state: "active",cycle: WatchCycle(generation: 1,phase: "preparing"))
        try await value.store.saveWatch(preparing,expectedRevision: record.revision)
        let remaining = value.grant.session.expiresAt-Date().timeIntervalSince1970
        if remaining > 0 { try await Task.sleep(for: .seconds(remaining+0.03)) }
        let peer = try ConnectionPeer.current()
        await #expect(throws: InvarError.self) { try await value.authority.authenticate(credential: value.grant.credential,epoch: value.epoch,peer: peer) }
        let operation = WorkspaceOperation.preparePlan(configurationPath: preparing.configurationPath,changeRevisionID: nil,budget: preparing.budget)
        let now = Date().timeIntervalSince1970
        let envelope = try await value.store.issueWatchEnvelope(watchID: preparing.id,operation: operation,epoch: value.epoch,now: now)
        #expect(envelope.sessionID == nil && envelope.watchID == preparing.id && envelope.hasCapabilityCeiling)
        #expect(envelope.capabilities == preparing.capabilities && !envelope.capabilities.contains(.nativeExecution))
        let duplicate = try await value.store.issueWatchEnvelope(watchID: preparing.id,operation: operation,epoch: value.epoch,now: now+0.01)
        #expect(duplicate == envelope)
        try await value.store.validateWatchRequest(envelope,operation: operation,now: now)
        await #expect(throws: InvarError.self) { try await value.store.issueEnvelope(envelope,now: now) }
        await #expect(throws: InvarError.self) { try await value.store.issueWatchEnvelope(watchID: preparing.id,operation: .preparePlan(configurationPath: "other.json",changeRevisionID: nil,budget: preparing.budget),epoch: value.epoch,now: now) }
        let child = RunDemand(id: Canonical.parts("invar.operation/2",[envelope.id]),envelopeID: envelope.id,principal: envelope.principal,origin: "watch",request: operation,planID: nil,changeRevisionID: nil,state: "queued",revision: 1,executionIDs: [],resultID: nil,failure: nil)
        _ = try await value.store.acceptDemand(envelope,demand: child,now: now)
        #expect(try await value.store.loadDemand(child.id) == child)
        let stopping = preparing.revising(state: "stopping",stopTarget: "stopped")
        try await value.store.saveWatch(stopping,expectedRevision: preparing.revision)
        let stopped = stopping.revising(state: "stopped",cycle: WatchCycle(generation: 1))
        await #expect(throws: InvarError.self) { try await value.store.saveWatch(stopped,expectedRevision: stopping.revision) }
        _ = try await value.store.finishDemandFailure(child.id,failure: InvarError("CANCELLED","Fixture queued child was never started"),cancelled: true)
        try await value.store.saveWatch(stopped,expectedRevision: stopping.revision)
        await #expect(throws: InvarError.self) { try await value.store.validateWatchRequest(envelope,operation: operation,now: now) }
    }

    @Test(arguments: [false,true]) func registrationStaysNonrunnableUntilParentCommitAndFailureNeverEnablesIt(_ cancel: Bool) async throws {
        let value = try await fixture()
        defer {
            await value.authority.shutdown()
            do { try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root) } catch { Issue.record(error) }
        }
        try await value.store.createWatch(value.record)
        #expect(try await value.store.loadWatch(value.record.id).state == "registering")
        #expect(try await value.store.watches(states: ["active"]).isEmpty)
        let parent = try await value.store.loadDemand(value.record.id)
        if cancel {
            _ = try await value.store.finishDemandFailure(parent.id,failure: InvarError("CANCELLED","Registration cancelled before commit"),cancelled: true)
            #expect(try await value.store.loadWatch(parent.id).state == "stopped")
            #expect(try await value.store.watches(states: ["active"]).isEmpty)
        } else {
            let completed = parent.transitioning(to: "completed",resultID: value.record.id)
            await #expect(throws: InvarError.self) { try await value.store.completeDemand(completed,run: nil,view: nil,expectedRevision: parent.revision-1) }
            #expect(try await value.store.loadWatch(parent.id).state == "registering")
            #expect(try await value.store.loadDemand(parent.id).state == "running")
            try await value.store.completeDemand(completed,run: nil,view: nil,expectedRevision: parent.revision)
            #expect(try await value.store.loadWatch(parent.id).state == "active")
            #expect(try await value.store.loadDemand(parent.id).state == "completed")
        }
    }

    @Test func verificationCannotUseAnUnpreparedPlanFromAnotherCycle() async throws {
        let value = try await fixture()
        defer {
            await value.authority.shutdown()
            do { try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root) } catch { Issue.record(error) }
        }
        let active = try await register(value)
        let preparing = active.revising(state: "active",cycle: WatchCycle(generation: 1,phase: "preparing"))
        try await value.store.saveWatch(preparing,expectedRevision: active.revision)
        let verifying = preparing.revising(state: "active",cycle: WatchCycle(generation: 1,phase: "verifying",planID: value.plan.id))
        try await value.store.saveWatch(verifying,expectedRevision: preparing.revision)
        await #expect(throws: InvarError.self) {
            try await value.store.issueWatchEnvelope(watchID: verifying.id,operation: .verify(planID: value.plan.id,changeRevisionID: nil,replayOfRunID: nil),epoch: value.epoch,now: Date().timeIntervalSince1970)
        }
    }

}

extension WatchRecordTests {
    @Test func pauseCleanupCannotOverwriteAConcurrentDurableStop() async throws {
        let value = try await fixture()
        defer { do { await value.authority.shutdown(); try await value.store.shutdown(); try FileManager.default.removeItem(at: value.root) } catch { Issue.record(error) } }
        let registered = try await register(value)
        let paused = try await value.store.pauseWatch(registered.id,failure: InvarError("POLICY_DENIED","Authority revoked"))
        #expect(paused.state == "paused")
        let stopping = try await value.store.beginWatchStop(registered.id,principal: registered.principal,target: "stopped")
        #expect(try await value.store.finishWatchPause(registered.id) == stopping)
        #expect(try await value.store.loadWatch(registered.id).state == "stopping")
    }
}
