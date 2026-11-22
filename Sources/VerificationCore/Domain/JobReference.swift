import Foundation

public struct JobReference: Codable, Sendable, Equatable, VerificationObligation {
    public let planID: String
    public let id: String
    public let backend: String
    public let required: Bool
    public let acceptsUnvalidatedModel: Bool
    public let acceptsFuzzBudget: Bool
    public let dependencies: [String]
    public let memoryMiB: Int
    public let descriptorID: String
    public let executionKey: String?
    public init(_ descriptor: JobDescriptor) throws {
        let job = descriptor.job
        planID = descriptor.planID; id = job.id; backend = job.backend; required = job.required
        acceptsUnvalidatedModel = job.acceptsUnvalidatedModel; acceptsFuzzBudget = job.acceptsFuzzBudget
        dependencies = job.dependencies; memoryMiB = job.memoryMiB
        descriptorID = try descriptor.identity(); executionKey = try ExecutionBinding.key(descriptor)
    }
}
