import Foundation

public struct FormalCheck: Codable, Sendable, Equatable {
    public let id: String
    public let source: String
    public let mode: String
    public let specification: String
    public let toolchain: String
    public let memoryMiB: Int?
    public var admissionMemoryMiB: Int { memoryMiB ?? (mode == "quantified" ? 2560 : 1536) }
    public let required: Bool
    public let acceptUnvalidatedModel: Bool
    public init(id: String, source: String, mode: String, specification: String, toolchain: String, required: Bool = true, acceptUnvalidatedModel: Bool = false,memoryMiB: Int? = nil) {
        self.memoryMiB = memoryMiB
        self.id = id
        self.source = source
        self.mode = mode
        self.specification = specification
        self.toolchain = toolchain
        self.required = required
        self.acceptUnvalidatedModel = acceptUnvalidatedModel
    }
}
