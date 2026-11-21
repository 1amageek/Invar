public protocol PolicyRepository: Sendable {
    func savePolicy(_ value: WorkspacePolicy,expectedRevision: Int) async throws
    func loadPolicy() async throws -> WorkspacePolicy?
    func savePrincipal(_ value: PrincipalGrant) async throws
    func principal(credentialDigest: String) async throws -> PrincipalGrant?
    func principal(identity: String) async throws -> PrincipalGrant?
}
