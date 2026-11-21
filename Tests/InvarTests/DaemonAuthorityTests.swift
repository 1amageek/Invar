import ArchitectureCore
import Foundation
import Testing
import VerificationCore
import VerificationDaemon
import VerificationStore

@Suite(.timeLimit(.minutes(1))) struct DaemonAuthorityTests {
    func policy(plan: VerificationPlan,peer: ConnectionPeer,revision: Int = 1,capabilities: Set<WorkspaceCapability> = [.read,.verification,.nativeExecution],entries: [InputEntry] = []) -> WorkspacePolicy {
        WorkspacePolicy(workspaceID: plan.body.input.workspaceID,engineIdentity: plan.body.executorIdentity,revision: revision,peers: [PeerGrant(binaryDigest: peer.binaryDigest,capabilities: capabilities)],approvals: [ContractApproval(configurationDigest: plan.body.configurationDigest,entries: entries)],sessionSeconds: 30,principalSeconds: 120,maximumSessions: 8,maximumConnections: 8,maximumEnvelopeSeconds: 60)
    }
    @Test func actualCodeIdentityCredentialsAndResumePreserveScopedAuthority() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let peer = try ConnectionPeer.current(), epoch = UUID().uuidString
        try await store.savePolicy(policy(plan: plan,peer: peer),expectedRevision: 0)
        try await store.activateEpoch(epoch,engineIdentity: plan.body.executorIdentity)
        let authority = DaemonSessionAuthority(repository: store,epoch: epoch)
        let first = try await authority.open(peer: peer,label: "untrusted label",requested: [.read,.verification,.nativeExecution,.administration])
        #expect(!first.session.grants.contains("administration"))
        let authenticated = try await authority.authenticate(credential: first.credential,epoch: epoch,peer: peer)
        #expect(authenticated.authority.principal == first.session.principal)
        let operation = WorkspaceOperation.verify(planID: plan.id,changeRevisionID: nil,replayOfRunID: nil)
        let allowed = try await authority.authority(principal: authenticated.authority.principal,operation: operation,policyRevision: 1,capabilityCeiling: [.read,.verification])
        #expect(allowed.capabilities == [.read,.verification])
        let original = try #require(try await store.principal(identity: first.session.principal))
        let resumed = try await authority.open(peer: peer,label: "a different label",requested: [.read],resumeCredential: first.resumeCredential)
        #expect(resumed.session.principal == first.session.principal)
        #expect(resumed.session.grants == ["read"])
        #expect(try await store.principal(identity: resumed.session.principal)?.expiresAt == original.expiresAt)
        await #expect(throws: InvarError.self) { try await authority.authority(principal: resumed.session.principal,operation: operation,policyRevision: 1,capabilityCeiling: [.read]) }
        await #expect(throws: InvarError.self) { try await authority.authenticate(credential: "invalid-credential-with-sufficient-length",epoch: epoch,peer: peer) }
        let peerBytes = try CanonicalJSON.encode(peer)
        var object = try #require(JSONSerialization.jsonObject(with: peerBytes) as? [String:Any])
        object["auditIdentity"] = "another-process-audit-token"
        let changedBytes = try JSONSerialization.data(withJSONObject: object)
        let otherPeer = try JSONDecoder().decode(ConnectionPeer.self,from: changedBytes)
        await #expect(throws: InvarError.self) { try await authority.authenticate(credential: first.credential,epoch: epoch,peer: otherPeer) }
        let secondPolicy = policy(plan: plan,peer: peer,revision: 2,capabilities: [.read])
        try await store.savePolicy(secondPolicy,expectedRevision: 1)
        await #expect(throws: InvarError.self) { try await authority.authenticate(credential: first.credential,epoch: epoch,peer: peer) }
        let narrowed = try await authority.open(peer: peer,label: nil,requested: [.read,.verification,.nativeExecution],resumeCredential: first.resumeCredential)
        #expect(narrowed.session.grants == ["read"])
        for name in ["verification.sqlite","verification.sqlite-wal"] {
            let path = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path.path) {
                let bytes = try Data(contentsOf: path)
                #expect(bytes.range(of: Data(first.credential.utf8)) == nil)
                #expect(bytes.range(of: Data(first.resumeCredential.utf8)) == nil)
            }
        }
        await authority.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test func requestEnvelopeCannotWidenItsRecordedSessionScope() async throws {
        let (store,plan,root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let peer = try ConnectionPeer.current(), epoch = UUID().uuidString
        try await store.savePolicy(policy(plan: plan,peer: peer),expectedRevision: 0)
        try await store.activateEpoch(epoch,engineIdentity: plan.body.executorIdentity)
        let authority = DaemonSessionAuthority(repository: store,epoch: epoch)
        let session = try await authority.open(peer: peer,label: nil,requested: [.read,.verification])
        let operation = WorkspaceOperation.verify(planID: plan.id,changeRevisionID: nil,replayOfRunID: nil)
        let now = Date().timeIntervalSince1970, fingerprint = try Canonical.identity(operation)
        func envelope(_ capabilities: [WorkspaceCapability],sessionID: String?) -> RequestEnvelope {
            RequestEnvelope(id: UUID().uuidString,sessionID: sessionID,capabilities: capabilities,requestKey: "scoped",principal: session.session.principal,workspaceID: plan.body.input.workspaceID,fingerprint: fingerprint,operation: operation.name,daemonEpoch: epoch,policyRevision: 1,expiresAt: now+15,retainUntil: now+60)
        }
        await #expect(throws: InvarError.self) { try await store.issueEnvelope(envelope([.verification,.nativeExecution],sessionID: session.session.id),now: now) }
        await #expect(throws: InvarError.self) { try await store.issueEnvelope(envelope([.verification],sessionID: nil),now: now) }
        let valid = envelope([.verification],sessionID: session.session.id)
        #expect(try await store.issueEnvelope(valid,now: now) == valid)
        await authority.shutdown(); try await store.shutdown(); try FileManager.default.removeItem(at: root)
    }
}
