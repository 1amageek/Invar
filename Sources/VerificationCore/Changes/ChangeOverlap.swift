import Foundation

public struct ChangeOverlap: Codable, Sendable, Equatable {
    public let changeID: String
    public let paths: [String]
    public init(changeID: String, paths: [String]) {
        self.changeID = changeID
        self.paths = paths
    }
}
