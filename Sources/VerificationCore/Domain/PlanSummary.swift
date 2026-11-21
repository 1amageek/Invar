public struct PlanSummary: Codable, Sendable, Equatable {
    public let id: String
    public let input: VerificationInput
    public let configurationDigest: String
    public let capturedScopeDigest: String
    public let budget: RunBudget
    public let jobIDs: [String]
    public let diagnostics: [String]
    public init(_ plan: SchedulingPlan) {
        id = plan.id; input = plan.input; configurationDigest = plan.configurationDigest; capturedScopeDigest = plan.capturedScopeDigest; budget = plan.budget
        jobIDs = plan.jobs.map(\.id); diagnostics = plan.diagnostics
    }
}
