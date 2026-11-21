import VerificationCore

public struct StaticBackend: VerificationBackend {
    private let evaluator: any ArchitecturePolicyEvaluating
    public init(evaluator: any ArchitecturePolicyEvaluating) { self.evaluator = evaluator }
    public func execute(_ context: BackendContext) async throws -> VerificationEvidence {
        try Task.checkCancellation()
        guard let policy = context.job.policy, policy.approved else { throw InvarError("UNAPPROVED_OBLIGATION", "Static policy is not approved", exitCode: 8) }
        let inventory = try FixedInputReader.inventory(context)
        return try evaluator.evaluate(policy, inventory: inventory)
    }
}
