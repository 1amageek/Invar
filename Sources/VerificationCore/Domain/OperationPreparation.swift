public struct OperationPreparation: Codable, Sendable, Equatable {
    public let operation: WorkspaceOperation
    public let key: String
    public let timeout: Double
    public init(operation: WorkspaceOperation,key: String,timeout: Double) { self.operation = operation; self.key = key; self.timeout = timeout }
}
