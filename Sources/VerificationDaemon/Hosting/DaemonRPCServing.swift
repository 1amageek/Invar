public protocol DaemonRPCServing: Sendable {
    func serve() async throws
    func shutdown() async throws
    var activeConnectionCount: Int { get async }
}
