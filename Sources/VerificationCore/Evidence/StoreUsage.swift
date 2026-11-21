import Foundation

public struct StoreUsage: Codable, Sendable, Equatable {
    public let observedBytes: Int
    public let observedFiles: Int
    public let reservedBytes: Int
    public let databaseReservedBytes: Int
    public let databaseBytes: Int
    public let reservationCount: Int
    public init(observedBytes: Int, observedFiles: Int, reservedBytes: Int, databaseReservedBytes: Int, databaseBytes: Int, reservationCount: Int) {
        self.observedBytes = observedBytes
        self.observedFiles = observedFiles
        self.reservedBytes = reservedBytes
        self.databaseReservedBytes = databaseReservedBytes
        self.databaseBytes = databaseBytes
        self.reservationCount = reservationCount
    }
}
