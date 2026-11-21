import Foundation

public struct ByteRegion: Codable, Sendable, Equatable {
    public let start: Int
    public let end: Int
    public let startLine: Int?
    public let endLine: Int?
    public init(start: Int, end: Int, startLine: Int?, endLine: Int?) {
        self.start = start
        self.end = end
        self.startLine = startLine
        self.endLine = endLine
    }
}
