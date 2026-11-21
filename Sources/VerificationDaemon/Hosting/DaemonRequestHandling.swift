import ArchitectureCore

public protocol DaemonRequestHandling: Sendable {
    // Nil closes the connection without an acknowledgement. A client must
    // reconcile a fixed operation receipt rather than infer its outcome.
    func handle(_ request: JSONValue,peer: ConnectionPeer,channel: DaemonRPCChannel) async throws -> JSONValue?
}
