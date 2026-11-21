import Foundation

public struct InvarError: Error, Codable, Sendable, Equatable, CustomStringConvertible {
    public let code: String
    public let message: String
    public let exitCode: Int32
    public init(_ code: String, _ message: String, exitCode: Int32 = 4) { self.code = code; self.message = message; self.exitCode = exitCode }
    public var description: String { "\(code): \(message)" }
}
