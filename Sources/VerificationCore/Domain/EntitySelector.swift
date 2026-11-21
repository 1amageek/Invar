import Foundation

public struct EntitySelector: Codable, Sendable, Equatable {
    public let id: String?
    public let kind: String?
    public let name: String?
    public let pathPrefix: String?
    public init(id: String? = nil, kind: String? = nil, name: String? = nil, pathPrefix: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.pathPrefix = pathPrefix
    }
}
