import VerificationCore

public struct ExplorerConnectionStatus: Sendable, Equatable {
    public enum State: String, Sendable { case ready, sourceOffline, approvalRequired }
    public let state: State
    public let failure: InvarError?
    public init(state: State,failure: InvarError? = nil) { self.state = state; self.failure = failure }
}
