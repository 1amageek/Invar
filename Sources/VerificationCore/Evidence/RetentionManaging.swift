import Foundation

public protocol RetentionManaging: Sendable {
    func storageReservations() async throws -> [StorageReservation]
    func abandonedReservationRoot(_ id: String) async throws -> URL?
    func discardAbandonedReservation(_ id: String) async throws
    func recoverRetiredObjects() async throws
    func reserve(_ reservation: StorageReservation) async throws
    func releaseReservation(_ id: String) async throws
    func usage() async throws -> StoreUsage
    func pin(_ value: RetentionPin) async throws
    func releasePin(_ id: String) async throws
    func prune(now: Double,maximumObjects: Int) async throws -> RetentionResult
}
