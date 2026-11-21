import Foundation

public struct SchedulingPlan: Codable, Sendable, Equatable {
    public static let maximumMetadataBytes = 1_048_576
    public let schemaVersion: Int
    public let id: String
    public let input: VerificationInput
    public let executorIdentity: String
    public let configurationDigest: String
    public let contractDigest: String
    public let capturedScopeDigest: String
    public let budget: RunBudget
    public let jobs: [JobReference]
    public let diagnostics: [String]
    public init(_ plan: VerificationPlan) throws {
        schemaVersion = 2; id = plan.id; input = plan.body.input; executorIdentity = plan.body.executorIdentity
        configurationDigest = plan.body.configurationDigest; budget = plan.body.budget; diagnostics = plan.body.diagnostics
        var references: [JobReference] = [], contracts: [String:InputEntry] = [:]
        for job in plan.body.jobs {
            let descriptor = ExecutionBinding.descriptor(plan: plan,job: job)
            let reference = try JobReference(descriptor); references.append(reference)
            var paths: [String] = []
            if let project = job.project { paths += project.contracts }
            if let formal = job.formal { paths.append(formal.specification) }
            if let native = job.native { paths += native.profile.harness }
            if let fuzz = job.fuzz { paths += fuzz.profile.harness + [fuzz.corpus] }
            for path in paths {
                guard let entry = job.inputs.first(where: { $0.path == path }), contracts[path].map({ $0 == entry }) ?? true else { throw InvarError("INPUT_MISMATCH","Plan contract bytes differ across obligations") }
                contracts[path] = entry
            }
        }
        jobs = references
        let entries = contracts.values.sorted { $0.path < $1.path }
        contractDigest = try Canonical.identity(entries)
        let budgetDigest = try Canonical.identity(budget)
        let obligations = try plan.body.jobs.sorted { $0.id < $1.id }.map(Canonical.identity)
        capturedScopeDigest = Canonical.parts("invar.captured-scope/2",[input.semanticDigest,executorIdentity,configurationDigest,contractDigest,budgetDigest]+obligations)
        let bytes = try Canonical.encode(self)
        guard bytes.count <= Self.maximumMetadataBytes else { throw InvarError("RESOURCE_LIMIT","Sealed DAG metadata exceeds its bounded profile",exitCode: 6) }
    }
}
