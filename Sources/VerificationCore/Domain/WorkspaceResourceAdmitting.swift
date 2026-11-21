public protocol WorkspaceResourceAdmitting: Sendable {
    func acquire(_ request: ResourceRequest) async throws
    func release(_ id: String) async
    func status(interests: Int) async -> SchedulingStatus
    func shutdown() async
}
