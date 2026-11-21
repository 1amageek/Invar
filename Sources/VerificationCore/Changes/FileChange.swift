import Foundation

public struct FileChange: Codable, Sendable, Equatable {
    public let path: String
    public let kind: String
    public let before: InputEntry?
    public let after: InputEntry?
    public let hunks: [FileHunk]
    public init(path: String, kind: String, before: InputEntry?, after: InputEntry?, hunks: [FileHunk]) {
        self.path = path
        self.kind = kind
        self.before = before
        self.after = after
        self.hunks = hunks
    }
}
