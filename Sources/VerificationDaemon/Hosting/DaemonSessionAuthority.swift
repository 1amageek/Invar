import ArchitectureCore
import Foundation
import VerificationCore

public actor DaemonSessionAuthority: DaemonAuthenticating {
    private struct Live {
        let session: AgentSession
        let auditIdentity: String
        let binaryDigest: String
        let codeIdentity: String
    }
    private let repository: any VerificationRepository
    private let epoch: String
    private var sessions: [String:Live] = [:]
    private var reservations = 0
    private var stopped = false
    public init(repository: any VerificationRepository,epoch: String) { self.repository = repository; self.epoch = epoch }
    public func open(peer: ConnectionPeer,label: String?,requested: Set<WorkspaceCapability>,resumeCredential: String? = nil) async throws -> ClientSessionGrant {
        guard !stopped, label.map({ $0.utf8.count <= 128 }) ?? true else { throw InvarError("AUTHENTICATION_REQUIRED","Session admission is stopped or invalid",exitCode: 8) }
        let policy = try await currentPolicy(), now = Date().timeIntervalSince1970
        sessions = sessions.filter { $0.value.session.expiresAt > now && $0.value.session.policyRevision == policy.revision }
        guard let approved = policy.peers.first(where: { $0.binaryDigest == peer.binaryDigest }), sessions.count + reservations < policy.maximumSessions else { throw InvarError("AUTHENTICATION_REQUIRED","Peer code is unapproved or session capacity is full",exitCode: 8) }
        reservations += 1; defer { reservations -= 1 }
        let secret: String, principal: PrincipalGrant
        if let resumeCredential {
            guard (32...256).contains(resumeCredential.utf8.count) else { throw InvarError("AUTHENTICATION_REQUIRED","Invalid principal resume credential",exitCode: 8) }
            secret = resumeCredential
            let digest = Canonical.digest(Data(secret.utf8))
            guard let value = try await repository.principal(credentialDigest: digest), value.workspaceID == policy.workspaceID, value.binaryDigest == peer.binaryDigest, value.codeIdentity == peer.codeIdentity, value.expiresAt > now else { throw InvarError("AUTHENTICATION_REQUIRED","Resume credential does not bind this approved peer/workspace",exitCode: 8) }
            principal = value
        } else {
            secret = UUID().uuidString + UUID().uuidString
            let granted = requested.intersection(Set(approved.capabilities)).subtracting([.administration])
            principal = PrincipalGrant(credentialDigest: Canonical.digest(Data(secret.utf8)),principal: UUID().uuidString,workspaceID: policy.workspaceID,binaryDigest: peer.binaryDigest,codeIdentity: peer.codeIdentity,initialAuditDigest: Canonical.digest(Data(peer.auditIdentity.utf8)),capabilities: granted,policyRevision: policy.revision,expiresAt: now + policy.principalSeconds)
            try await repository.savePrincipal(principal)
        }
        let granted = requested.intersection(Set(approved.capabilities)).intersection(Set(principal.capabilities)).subtracting([.administration])
        let session = AgentSession(id: UUID().uuidString,principal: principal.principal,agentLabel: label,grants: granted.map(\.rawValue).sorted(),policyRevision: policy.revision,expiresAt: min(now + policy.sessionSeconds,principal.expiresAt))
        try await repository.saveAgentSession(session)
        let current = try await currentPolicy()
        guard !stopped, current.revision == policy.revision else { throw InvarError("POLICY_DENIED","Policy changed during session admission",exitCode: 8) }
        let credential = UUID().uuidString + UUID().uuidString
        sessions[Canonical.digest(Data(credential.utf8))] = Live(session: session,auditIdentity: peer.auditIdentity,binaryDigest: peer.binaryDigest,codeIdentity: peer.codeIdentity)
        return ClientSessionGrant(workspaceID: policy.workspaceID,epoch: epoch,engineIdentity: policy.engineIdentity,session: session,credential: credential,resumeCredential: secret)
    }
    public func authenticate(credential: String,epoch: String,peer: ConnectionPeer) async throws -> AuthenticatedSession {
        guard !stopped, self.epoch == epoch, (32...256).contains(credential.utf8.count), let live = sessions[Canonical.digest(Data(credential.utf8))], live.auditIdentity == peer.auditIdentity, live.binaryDigest == peer.binaryDigest, live.codeIdentity == peer.codeIdentity, live.session.expiresAt > Date().timeIntervalSince1970 else { throw InvarError("AUTHENTICATION_REQUIRED","Session credential is expired or belongs to another actual peer",exitCode: 8) }
        let policy = try await currentPolicy()
        guard !stopped, policy.revision == live.session.policyRevision, let approved = policy.peers.first(where: { $0.binaryDigest == peer.binaryDigest }) else { throw InvarError("POLICY_DENIED","Session policy was revoked",exitCode: 8) }
        let capabilities = Set(live.session.grants.compactMap(WorkspaceCapability.init(rawValue:))).intersection(Set(approved.capabilities))
        let authority = OperationAuthority(principal: live.session.principal,policyRevision: policy.revision,capabilities: capabilities)
        return AuthenticatedSession(session: live.session,authority: authority)
    }
    public func authority(principal: String,operation: WorkspaceOperation,policyRevision: Int,capabilityCeiling: Set<WorkspaceCapability>?) async throws -> OperationAuthority {
        let policy = try await currentPolicy()
        guard !stopped, policy.revision == policyRevision, let grant = try await repository.principal(identity: principal), grant.workspaceID == policy.workspaceID, grant.expiresAt > Date().timeIntervalSince1970, let peer = policy.peers.first(where: { $0.binaryDigest == grant.binaryDigest }) else { throw InvarError("POLICY_DENIED","Accepted principal authority expired or was revoked",exitCode: 8) }
        let allowed = Set(grant.capabilities).intersection(Set(peer.capabilities)).subtracting([.administration])
        let capabilities = capabilityCeiling.map { allowed.intersection($0) } ?? allowed
        let required = operation.requiredCapability
        guard capabilities.contains(required) else { throw InvarError("POLICY_DENIED","Principal lacks this operation capability",exitCode: 8) }
        let planID: String?, executes: Bool
        switch operation {
        case .verify(let id,_,_,_): planID = id; executes = true
        case .reconcile(let id,_): planID = id; executes = false
        default: planID = nil; executes = false
        }
        if let id = planID {
            let plan = try await repository.schedulingPlan(id)
            guard plan.input.workspaceID == policy.workspaceID, plan.executorIdentity == policy.engineIdentity else { throw InvarError("EXECUTOR_MISMATCH","Plan differs from current host workspace/engine") }
            if executes, plan.jobs.contains(where: { ["native","fuzz","project"].contains($0.backend) }), !capabilities.contains(.nativeExecution) { throw InvarError("POLICY_DENIED","Native execution requires a separate host grant",exitCode: 8) }
            if executes, plan.jobs.contains(where: { $0.backend == "project" }), !capabilities.contains(.userLeanExecution) { throw InvarError("POLICY_DENIED","Project specification checking requires user Lean execution authority",exitCode: 8) }
            var approved = false
            if plan.jobs.count == 1, let job = plan.jobs.first, job.backend == "modelGeneration" {
                let descriptor = try await repository.loadDescriptor(job.descriptorID)
                if executes {
                    guard let source = descriptor.job.modelSource, let node = operation.verificationNode,
                        node.snapshotID == plan.input.snapshotID, node.entityID == source.id else {
                        throw InvarError("INPUT_MISMATCH","Model generation must remain bound to its selected source")
                    }
                }
                approved = true
            }
            for approval in policy.approvals where approval.configurationDigest == plan.configurationDigest {
                let digest = try Canonical.identity(approval.entries)
                if digest == plan.contractDigest { approved = true; break }
            }
            guard approved else { throw InvarError("APPROVAL_REQUIRED","Configuration/oracle/harness/corpus bytes have no exact host approval",exitCode: 8) }
        }
        let current = try await currentPolicy()
        guard !stopped, current.revision == policy.revision else { throw InvarError("POLICY_DENIED","Policy changed during operation authorization",exitCode: 8) }
        return OperationAuthority(principal: principal,policyRevision: policy.revision,capabilities: capabilities)
    }
    private func currentPolicy() async throws -> WorkspacePolicy {
        guard let value = try await repository.loadPolicy() else { throw InvarError("APPROVAL_REQUIRED","Workspace has no host policy",exitCode: 8) }
        return value
    }
    public func invalidate() { sessions.removeAll() }
    public func shutdown() { stopped = true; sessions.removeAll() }
}
