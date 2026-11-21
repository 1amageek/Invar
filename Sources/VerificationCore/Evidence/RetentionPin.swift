import Foundation

public struct RetentionPin: Codable, Sendable, Equatable {
    public let id: String
    public let ownerKind: String
    public let ownerID: String
    public let objectKind: String
    public let objectID: String
    public let expiresAt: Double?
    public init(id: String, ownerKind: String, ownerID: String, objectKind: String, objectID: String, expiresAt: Double?) {
        self.id = id
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.objectKind = objectKind
        self.objectID = objectID
        self.expiresAt = expiresAt
    }
}
