public struct PreparedOperation: Codable, Sendable, Equatable {
    public let envelope: RequestEnvelope
    public let operation: WorkspaceOperation
    public init(envelope: RequestEnvelope,operation: WorkspaceOperation) { self.envelope = envelope; self.operation = operation }
}
