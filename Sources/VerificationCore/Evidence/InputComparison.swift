import Foundation

public struct InputComparison: Codable, Sendable, Equatable {
    public let target: VerificationInput?
    public let status: String
    public let basis: String
    public let unknownBoundaries: [String]
    public init(target: VerificationInput?,status: String,basis: String,unknownBoundaries: [String] = []) { self.target = target; self.status = status; self.basis = basis; self.unknownBoundaries = unknownBoundaries }
}
