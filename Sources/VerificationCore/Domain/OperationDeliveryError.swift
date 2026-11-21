public struct OperationDeliveryError: Error, Codable, Sendable, Equatable {
    public let prepared: PreparedOperation
    public let cause: InvarError
    public init(prepared: PreparedOperation,cause: InvarError) { self.prepared = prepared; self.cause = cause }
}
