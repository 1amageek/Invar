public protocol InputApplicabilityChecking: Sendable {
    func applicability(of plan: SchedulingPlan) async throws -> InputComparison
}
