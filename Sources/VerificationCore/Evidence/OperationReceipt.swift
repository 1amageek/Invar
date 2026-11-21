import Foundation

public struct OperationReceipt: Codable, Sendable, Equatable {
    public let id: String
    public let operationID: String
    public let fingerprint: String
    public let acceptedAt: Double
    public let daemonEpoch: String
    public init(id: String, operationID: String, fingerprint: String, acceptedAt: Double, daemonEpoch: String) {
        self.id = id
        self.operationID = operationID
        self.fingerprint = fingerprint
        self.acceptedAt = acceptedAt
        self.daemonEpoch = daemonEpoch
    }
}
