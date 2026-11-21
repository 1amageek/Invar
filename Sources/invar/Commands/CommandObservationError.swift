import VerificationCore

struct CommandObservationError: Error, Codable, Sendable {
    let receipt: OperationReceipt
    let cause: InvarError
}
