public struct ProviderActionSummary: Codable, Sendable, Equatable {
    public let id: String
    public let jobID: String?
    public let state: String
    public let operationState: String?
    public let planID: String?
    public let changeRevisionID: String?
    public let resultID: String?
    public let view: ViewReference?
    public let diagnosticCode: String?
    public init(_ state: ProviderActionState,demand: RunDemand?) {
        id = state.id; jobID = state.jobID; self.state = state.state; operationState = demand?.state
        planID = demand?.planID; changeRevisionID = demand?.changeRevisionID; resultID = demand?.resultID; view = demand?.view
        diagnosticCode = state.failure?.code ?? demand?.failure?.code
    }
}
