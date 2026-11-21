import Foundation

public struct RecordDifference: Codable, Sendable, Equatable {
    public let category: String
    public let added: [String]
    public let removed: [String]
    public let changed: [String]
    public init(category: String, added: [String], removed: [String], changed: [String]) {
        self.category = category
        self.added = added
        self.removed = removed
        self.changed = changed
    }
}
