import Foundation

public struct PlanBody: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let input: VerificationInput
    public let executorIdentity: String
    public let configurationDigest: String
    public let jobs: [VerificationJob]
    public let budget: RunBudget
    public let diagnostics: [String]
    public init(schemaVersion: Int = 2, input: VerificationInput, executorIdentity: String, configurationDigest: String, jobs: [VerificationJob], budget: RunBudget, diagnostics: [String] = []) {
        self.schemaVersion = schemaVersion
        self.input = input
        self.executorIdentity = executorIdentity
        self.configurationDigest = configurationDigest
        self.jobs = jobs
        self.budget = budget
        self.diagnostics = diagnostics
    }
}
