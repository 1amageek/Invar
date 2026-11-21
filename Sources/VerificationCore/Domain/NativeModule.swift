import Foundation

public struct NativeModule: Codable, Sendable, Equatable {
    public let name: String
    public let sources: [String]
    public let dependencies: [String]
    public init(name: String, sources: [String], dependencies: [String] = []) { self.name = name; self.sources = sources; self.dependencies = dependencies }
}
