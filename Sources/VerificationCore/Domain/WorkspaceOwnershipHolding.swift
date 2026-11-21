public protocol WorkspaceOwnershipHolding: Sendable {
    var paths: DaemonEndpointPaths { get }
    func release() async throws
}
