public protocol ProviderActionRepository: Sendable {
    func createProviderAction(_ registration: ProviderActionRegistration) async throws
    func providerAction(_ id: String) async throws -> ProviderActionRegistration?
    func providerActionState(_ id: String) async throws -> ProviderActionState
    func saveProviderActionState(_ value: ProviderActionState,expectedRevision: Int) async throws
    func providerActionIDs() async throws -> [String]
    func providerActionForDemand(_ id: String) async throws -> ProviderActionRegistration?
}
