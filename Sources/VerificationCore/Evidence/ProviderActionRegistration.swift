import Foundation

/// Private preflight; opaque owner records and resume authority are never public projections.
public struct ProviderActionRegistration: Codable, Sendable, Equatable {
    public let id: String
    public let envelope: RequestEnvelope
    public let operation: WorkspaceOperation
    public let input: VerificationInput
    public let sourceFingerprint: String
    public let intent: Data
    public let runRequestID: String
    public let run: Data
    public let expiresAt: Double
    public init(id: String,envelope: RequestEnvelope,operation: WorkspaceOperation,input: VerificationInput,sourceFingerprint: String,intent: Data,runRequestID: String,run: Data,expiresAt: Double) {
        self.id = id; self.envelope = envelope; self.operation = operation; self.input = input; self.sourceFingerprint = sourceFingerprint
        self.intent = intent; self.runRequestID = runRequestID; self.run = run; self.expiresAt = expiresAt
    }
}
