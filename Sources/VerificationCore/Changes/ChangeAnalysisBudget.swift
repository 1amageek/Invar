import Foundation

public struct ChangeAnalysisBudget: Codable, Sendable, Equatable {
    public let maximumFiles: Int
    public let maximumBytes: Int
    public let maximumRecords: Int
    public let maximumVisits: Int
    public let maximumOutputBytes: Int
    public init(maximumFiles: Int, maximumBytes: Int, maximumRecords: Int, maximumVisits: Int, maximumOutputBytes: Int) {
        self.maximumFiles = maximumFiles
        self.maximumBytes = maximumBytes
        self.maximumRecords = maximumRecords
        self.maximumVisits = maximumVisits
        self.maximumOutputBytes = maximumOutputBytes
    }
}
