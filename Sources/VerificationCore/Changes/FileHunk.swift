import Foundation

public struct FileHunk: Codable, Sendable, Equatable {
    public let before: ByteRegion?
    public let after: ByteRegion?
    public let encoding: String
    public init(before: ByteRegion?, after: ByteRegion?, encoding: String) {
        self.before = before
        self.after = after
        self.encoding = encoding
    }
}
