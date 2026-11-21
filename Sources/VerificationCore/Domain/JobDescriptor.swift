import Foundation

public struct JobDescriptor: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let planID: String
    public let input: VerificationInput
    public let job: VerificationJob
    public let executorIdentity: String
    public let budget: RunBudget
    public init(planID: String,input: VerificationInput,job: VerificationJob,executorIdentity: String,budget: RunBudget) {
        schemaVersion = 2; self.planID = planID; self.input = input; self.job = job; self.executorIdentity = executorIdentity; self.budget = budget
    }
    public func identity() throws -> String { try Canonical.identity(self) }
}
