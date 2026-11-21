import VerificationCore

public protocol FormalReadServing: Sendable {
    func query(_ query: FormalReadQuery,session: AgentSession,epoch: String) async throws -> FormalReadResult
    func expire() async throws
    func shutdown() async throws
}
