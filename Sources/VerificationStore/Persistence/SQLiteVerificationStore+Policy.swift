import Foundation
import VerificationCore

extension SQLiteVerificationStore {
    public func savePolicy(_ value: WorkspacePolicy,expectedRevision: Int) throws {
        try ensureAccepting(); try value.validate(retentionSeconds: policy.retentionSeconds)
        try transaction {
            let current = try loadPolicy()
            guard value.revision == expectedRevision + 1, (current?.revision ?? 0) == expectedRevision,
                current.map({ $0.workspaceID == value.workspaceID && $0.engineIdentity == value.engineIdentity }) ?? true else { throw InvarError("REVISION_CONFLICT","Policy workspace/engine/revision differs") }
            let id = try Canonical.identity(value), bytes = try Canonical.encode(value)
            try database.insert("policy",id: id,bytes: bytes)
            try database.advance("policy",id: "active",expectedRevision: expectedRevision,recordID: id)
        }
    }
    public func loadPolicy() throws -> WorkspacePolicy? {
        try ensureAccepting()
        guard let head = try database.head("policy",id: "active"), let bytes = try database.load("policy",id: head.recordID) else { return nil }
        let value = try JSONDecoder().decode(WorkspacePolicy.self,from: bytes)
        try value.validate(retentionSeconds: policy.retentionSeconds)
        guard value.revision == head.revision, try Canonical.identity(value) == head.recordID else { throw InvarError("STORE_INTEGRITY","Policy revision/digest differs") }
        return value
    }
    public func savePrincipal(_ value: PrincipalGrant) throws {
        try ensureAccepting(); try safeID(value.credentialDigest); try safeID(value.principal)
        guard value.expiresAt.isFinite, value.expiresAt > Date().timeIntervalSince1970, value.policyRevision > 0, value.credentialDigest.utf8.count == 64, value.credentialDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }), value.binaryDigest.utf8.count == 64, value.initialAuditDigest.utf8.count == 64, !value.codeIdentity.isEmpty, value.codeIdentity.utf8.count <= 512, Set(value.capabilities).count == value.capabilities.count else { throw InvarError("INVALID_SESSION","Invalid principal credential binding") }
        guard let policy = try loadPolicy(), value.workspaceID == policy.workspaceID, value.policyRevision == policy.revision, value.expiresAt <= Date().timeIntervalSince1970 + policy.principalSeconds,
            let peer = policy.peers.first(where: { $0.binaryDigest == value.binaryDigest }), Set(value.capabilities).isSubset(of: Set(peer.capabilities)) else { throw InvarError("POLICY_DENIED","Principal exceeds current approved peer authority",exitCode: 8) }
        try transaction {
            let bytes = try Canonical.encode(value)
            try database.insert("principal",id: value.credentialDigest,bytes: bytes)
            let policyID = try Canonical.identity(policy)
            try database.link(ownerKind: "principal",ownerID: value.credentialDigest,targetKind: "policy",targetID: policyID)
            let index = try Canonical.encode(["credentialDigest":value.credentialDigest])
            try database.insert("principalIdentity",id: value.principal,bytes: index)
            try database.link(ownerKind: "principalIdentity",ownerID: value.principal,targetKind: "principal",targetID: value.credentialDigest)
        }
    }
    public func principal(credentialDigest: String) throws -> PrincipalGrant? {
        try ensureAccepting(); try safeID(credentialDigest)
        guard let bytes = try database.load("principal",id: credentialDigest) else { return nil }
        let value = try JSONDecoder().decode(PrincipalGrant.self,from: bytes)
        guard value.credentialDigest == credentialDigest else { throw InvarError("STORE_INTEGRITY","Principal credential digest differs") }; return value
    }
    public func principal(identity: String) throws -> PrincipalGrant? {
        try ensureAccepting(); try safeID(identity)
        guard let bytes = try database.load("principalIdentity",id: identity) else { return nil }
        let index = try JSONDecoder().decode([String:String].self,from: bytes)
        guard let digest = index["credentialDigest"], let value = try principal(credentialDigest: digest), value.principal == identity else { throw InvarError("STORE_INTEGRITY","Principal identity index differs") }
        return value
    }
}
