import Foundation

public struct AttributionAssessment: Codable, Sendable, Equatable {
    public let kind: String
    public let basis: [String]
    public let overlappingChangeIDs: [String]
    public let unclaimedPaths: [String]
    public init(kind: String, basis: [String], overlappingChangeIDs: [String], unclaimedPaths: [String]) {
        self.kind = kind
        self.basis = basis
        self.overlappingChangeIDs = overlappingChangeIDs
        self.unclaimedPaths = unclaimedPaths
    }
}
