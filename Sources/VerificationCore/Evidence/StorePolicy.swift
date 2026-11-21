import Foundation

public struct StorePolicy: Codable, Sendable, Equatable {
    public let maximumRetainedBytes: Int
    public let maximumDatabaseBytes: Int
    public let failureReserveBytes: Int
    public let maximumRecords: Int
    public let maximumFiles: Int
    public let maximumReservations: Int
    public let retentionSeconds: Double
    public init(maximumRetainedBytes: Int, maximumDatabaseBytes: Int, failureReserveBytes: Int, maximumRecords: Int, maximumFiles: Int, maximumReservations: Int, retentionSeconds: Double) {
        self.maximumRetainedBytes = maximumRetainedBytes
        self.maximumDatabaseBytes = maximumDatabaseBytes
        self.failureReserveBytes = failureReserveBytes
        self.maximumRecords = maximumRecords
        self.maximumFiles = maximumFiles
        self.maximumReservations = maximumReservations
        self.retentionSeconds = retentionSeconds
    }
    // This development policy derives capacity from the existing two-worker,
    // 512 MiB workspace and 256 MiB capture profiles. Callers can select all limits.
    public static let development = StorePolicy(maximumRetainedBytes: 256 * 1024 * 1024 + 3 * 512 * 1024 * 1024 + 3 * 65 * 1024 * 1024,maximumDatabaseBytes: 65 * 1024 * 1024,failureReserveBytes: 1024 * 1024,maximumRecords: 1024 + 64 * 500 * 3,maximumFiles: 250_000,maximumReservations: 64,retentionSeconds: 3600)
    public func validate() throws {
        guard maximumDatabaseBytes <= Int.max / 4, maximumRecords < Int.max, maximumFiles < Int.max, maximumReservations < Int.max, maximumRetainedBytes > 3 * maximumDatabaseBytes, maximumDatabaseBytes > failureReserveBytes, failureReserveBytes > 0, maximumRecords > 0, maximumFiles > 0, maximumReservations > 0, retentionSeconds.isFinite, retentionSeconds > 0 else { throw InvarError("INVALID_POLICY","Invalid Store resource policy",exitCode: 2) }
    }
}
