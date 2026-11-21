import Foundation

public protocol VerificationPlanning: Sendable {
    func build(inventory: ScopeInventory, inputID: String, executorIdentity: String, configuration: VerificationConfiguration,
        specifications: [String: Data], compilations: [String: PreparedFormalUnit], toolchains: [String: String], budget: RunBudget) throws -> VerificationPlan
}
