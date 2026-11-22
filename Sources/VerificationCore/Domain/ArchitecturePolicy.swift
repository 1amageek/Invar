import Foundation

public struct ArchitecturePolicy: Codable, Sendable, Equatable {
    public let id: String
    public let kind: String
    public let relations: [String]
    public let from: EntitySelector?
    public let to: EntitySelector?
    public let required: Bool
    public init(id: String, kind: String, relations: [String] = ["dependsOn", "imports", "calls"], from: EntitySelector? = nil, to: EntitySelector? = nil, required: Bool = true) {
        self.id = id
        self.kind = kind
        self.relations = relations
        self.from = from
        self.to = to
        self.required = required
    }
}
