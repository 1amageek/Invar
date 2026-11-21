import VerificationCore

public protocol DaemonStateReading: Sendable {
    func status(activeOperations: Int,watchCount: Int) async -> DaemonStatus
}
