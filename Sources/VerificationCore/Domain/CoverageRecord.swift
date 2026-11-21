import Foundation

public struct CoverageRecord: Codable, Sendable, Equatable {
    public let producer: String
    public let scope: String
    public let freshness: String
    public let completeness: String
    public let exclusions: [String]
    public init(producer: String, scope: String, freshness: String, completeness: String, exclusions: [String] = []) {
        self.producer = producer
        self.scope = scope
        self.freshness = freshness
        self.completeness = completeness
        self.exclusions = exclusions
    }
}
