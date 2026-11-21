public protocol VerificationPlanningClient: Sendable {
    func preparePlan(configurationPath: String,changeRevisionID: String?,budget: RunBudget,key: String,timeout: Double) async throws -> OperationReceipt
    func plan(_ id: String) async throws -> PlanSummary
}
