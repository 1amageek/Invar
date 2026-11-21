import Foundation

public protocol ArchitecturePolicyEvaluating: Sendable {
    func evaluate(_ policy: ArchitecturePolicy, inventory: ScopeInventory) throws -> VerificationEvidence
}
