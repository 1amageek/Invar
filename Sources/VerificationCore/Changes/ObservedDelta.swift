import Foundation

public struct ObservedDelta: Codable, Sendable, Equatable {
    public let files: [FileChange]
    public let records: [RecordDifference]
    public let contextChanged: Bool
    public let oraclePaths: [String]
    public let unknownBoundaries: [String]
    public init(files: [FileChange], records: [RecordDifference], contextChanged: Bool, oraclePaths: [String], unknownBoundaries: [String]) {
        self.files = files
        self.records = records
        self.contextChanged = contextChanged
        self.oraclePaths = oraclePaths
        self.unknownBoundaries = unknownBoundaries
    }
}
