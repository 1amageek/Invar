import Foundation

public struct FactRecord: Codable, Sendable, Equatable {
    public let id: String
    public let kind: String
    public let source: String
    public let target: String
    public let producer: String
    public let scope: String
    public let evidenceIDs: [String]
    public init(id: String, kind: String, source: String, target: String, producer: String, scope: String, evidenceIDs: [String] = []) {
        self.id = id
        self.kind = kind
        self.source = source
        self.target = target
        self.producer = producer
        self.scope = scope
        self.evidenceIDs = evidenceIDs
    }
}
