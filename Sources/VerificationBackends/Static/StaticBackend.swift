import VerificationCore

public struct StaticBackend: VerificationBackend {
    private let evaluator: any ArchitecturePolicyEvaluating
    public init(evaluator: any ArchitecturePolicyEvaluating) { self.evaluator = evaluator }
    public func execute(_ context: BackendContext) async throws -> VerificationEvidence {
        try Task.checkCancellation()
        guard let policy = context.job.policy else { throw InvarError("INVALID_PLAN", "Static job is missing its configured rule", exitCode: 8) }
        let inventory = try FixedInputReader.inventory(context)
        return try evaluator.evaluate(policy, inventory: inventory)
    }
}
