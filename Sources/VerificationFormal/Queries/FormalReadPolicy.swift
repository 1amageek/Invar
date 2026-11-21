import FormalEvidence
import VerificationCore

public struct FormalReadPolicy: Sendable, Equatable {
    public let maximumReaders: Int
    public let leaseSeconds: Double
    public let maximumBudget: EvidenceReadBudget
    public init(maximumReaders: Int,leaseSeconds: Double,maximumBudget: EvidenceReadBudget) {
        self.maximumReaders = maximumReaders; self.leaseSeconds = leaseSeconds; self.maximumBudget = maximumBudget
    }
    public static let development = FormalReadPolicy(maximumReaders: 4,leaseSeconds: 60,maximumBudget: EvidenceReadBudget(maximumDatabaseBytes: 536870912,maximumRecordBytes: 262144,maximumPageBytes: 262144,maximumNodes: 128,maximumEdges: 256,maximumTraversalNodes: 4096,maximumCursors: 4))
    public func validate() throws {
        guard (1...32).contains(maximumReaders), maximumBudget.maximumNodes <= 500, maximumBudget.maximumEdges <= 1500,
            maximumBudget.maximumTraversalNodes <= 1_000_000, maximumBudget.maximumCursors <= 16, leaseSeconds.isFinite, (1...300).contains(leaseSeconds) else { throw InvarError("INVALID_POLICY","Formal reader lease policy is invalid") }
        try accepts(maximumBudget)
    }
    public func accepts(_ budget: EvidenceReadBudget) throws {
        guard budget.maximumDatabaseBytes > 0, budget.maximumDatabaseBytes <= maximumBudget.maximumDatabaseBytes,
            budget.maximumRecordBytes > 0, budget.maximumRecordBytes <= maximumBudget.maximumRecordBytes,
            budget.maximumPageBytes >= budget.maximumRecordBytes, budget.maximumPageBytes <= maximumBudget.maximumPageBytes, budget.maximumPageBytes <= 524288,
            budget.maximumNodes >= 2, budget.maximumNodes <= maximumBudget.maximumNodes,
            budget.maximumEdges > 0, budget.maximumEdges <= maximumBudget.maximumEdges,
            budget.maximumTraversalNodes > 0, budget.maximumTraversalNodes <= maximumBudget.maximumTraversalNodes,
            budget.maximumCursors > 0, budget.maximumCursors <= maximumBudget.maximumCursors else { throw InvarError("RESOURCE_LIMIT","Formal read budget exceeds host policy or has invalid bounds",exitCode: 6) }
    }
}
