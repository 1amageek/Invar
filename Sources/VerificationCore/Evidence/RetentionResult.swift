import Foundation

public struct RetentionResult: Codable, Sendable, Equatable {
    public let removedObjects: [String]
    public let retainedBytes: Int
    public let fileCount: Int
    public init(removedObjects: [String], retainedBytes: Int, fileCount: Int) {
        self.removedObjects = removedObjects
        self.retainedBytes = retainedBytes
        self.fileCount = fileCount
    }
}
