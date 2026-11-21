import Foundation

public struct ClaimedFileState: Codable, Sendable, Equatable {
    public let path: String
    public let digest: String?
    public init(path: String, digest: String?) {
        self.path = path
        self.digest = digest
    }
}
