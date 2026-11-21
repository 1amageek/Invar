import Foundation

public struct ChangeClaim: Codable, Sendable, Equatable {
    public let intent: String
    public let paths: [String]
    public let entityIDs: [String]
    public let patchDigest: String?
    public let expectedFiles: [ClaimedFileState]
    public init(intent: String, paths: [String], entityIDs: [String], patchDigest: String?, expectedFiles: [ClaimedFileState]) {
        self.intent = intent
        self.paths = paths
        self.entityIDs = entityIDs
        self.patchDigest = patchDigest
        self.expectedFiles = expectedFiles
    }
}
