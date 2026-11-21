import Foundation

public struct InputEntry: Codable, Sendable, Equatable {
    public let path: String
    public let digest: String
    public let byteCount: Int
    public init(path: String, digest: String, byteCount: Int) {
        self.path = path
        self.digest = digest
        self.byteCount = byteCount
    }
}
