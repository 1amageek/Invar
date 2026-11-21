import Foundation

public struct EntityRecord: Codable, Sendable, Equatable {
    public let id: String
    public let kind: String
    public let language: String
    public let name: String
    public let path: String?
    public let sourceDigest: String?
    public let startByte: Int?
    public let endByte: Int?
    public var supportsModelSelection: Bool {
        ["file", "function"].contains(kind) || language == "swift" && ["type", "method", "actor", "extension", "field"].contains(kind)
    }
    public init(id: String, kind: String, language: String, name: String, path: String? = nil, sourceDigest: String? = nil, startByte: Int? = nil, endByte: Int? = nil) {
        self.id = id
        self.kind = kind
        self.language = language
        self.name = name
        self.path = path
        self.sourceDigest = sourceDigest
        self.startByte = startByte
        self.endByte = endByte
    }
}
