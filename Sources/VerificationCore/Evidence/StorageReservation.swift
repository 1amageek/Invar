import Foundation

public struct StorageReservation: Codable, Sendable, Equatable {
    public let id: String
    public let relativeRoot: String
    public let maximumBytes: Int
    public let maximumFiles: Int
    public init(id: String, relativeRoot: String, maximumBytes: Int, maximumFiles: Int) {
        self.id = id
        self.relativeRoot = relativeRoot
        self.maximumBytes = maximumBytes
        self.maximumFiles = maximumFiles
    }
}
