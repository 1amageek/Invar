import Foundation

public protocol VerificationBackend: Sendable {
    func execute(_ context: BackendContext) async throws -> VerificationEvidence
}
