import Foundation

public struct VerificationJob: Codable, Sendable, Equatable, VerificationObligation {
    public let id: String
    public let backend: String
    public let required: Bool
    public let dependencies: [String]
    public let policy: ArchitecturePolicy?
    public let native: NativeCheck?
    public let fuzz: FuzzCheck?
    public let project: ProjectCheck?
    public let modelSource: EntityRecord?
    public let formal: FormalCheck?
    public let inputs: [InputEntry]
    public let oracle: InputEntry?
    public let compilation: PreparedFormalUnit?
    public let toolchainIdentity: String?
    public let memoryMiB: Int
    public var acceptsUnvalidatedModel: Bool { formal?.acceptUnvalidatedModel == true }
    public var acceptsFuzzBudget: Bool { fuzz?.acceptNoViolationObservedWithinBudget == true }
    public init(id: String, backend: String, required: Bool, dependencies: [String] = [], policy: ArchitecturePolicy? = nil, formal: FormalCheck? = nil, inputs: [InputEntry] = [], oracle: InputEntry? = nil, compilation: PreparedFormalUnit? = nil, toolchainIdentity: String? = nil, memoryMiB: Int = 64, native: NativeCheck? = nil, fuzz: FuzzCheck? = nil, modelSource: EntityRecord? = nil, project: ProjectCheck? = nil) {
        self.project = project
        self.modelSource = modelSource
        self.id = id
        self.backend = backend
        self.required = required
        self.dependencies = dependencies
        self.policy = policy
        self.formal = formal
        self.native = native
        self.fuzz = fuzz
        self.inputs = inputs.sorted { $0.path < $1.path }
        self.oracle = oracle
        self.compilation = compilation
        self.toolchainIdentity = toolchainIdentity
        self.memoryMiB = memoryMiB
    }
}
