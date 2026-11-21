import Foundation

public struct BackendContext: Codable, Sendable, Equatable {
    public let descriptor: JobDescriptor
    public let descriptorID: String
    public let nativeExecutionAllowed: Bool
    public let ownerPID: Int32
    public let timeoutSeconds: Double
    public let inputRoot: URL
    public let outputRoot: URL
    public let compilationRoot: URL?
    public var job: VerificationJob { descriptor.job }
    public var planID: String { descriptor.planID }
    public var input: VerificationInput { descriptor.input }
    public var budget: RunBudget { descriptor.budget }
    public var executorIdentity: String { descriptor.executorIdentity }
    public init(descriptor: JobDescriptor,descriptorID: String,inputRoot: URL,outputRoot: URL,compilationRoot: URL? = nil,timeoutSeconds: Double,ownerPID: Int32,nativeExecutionAllowed: Bool = false) {
        self.descriptor = descriptor; self.descriptorID = descriptorID; self.inputRoot = inputRoot; self.outputRoot = outputRoot; self.compilationRoot = compilationRoot; self.timeoutSeconds = timeoutSeconds; self.ownerPID = ownerPID; self.nativeExecutionAllowed = nativeExecutionAllowed
    }
}
