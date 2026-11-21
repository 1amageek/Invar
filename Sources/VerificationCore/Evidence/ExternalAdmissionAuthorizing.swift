/// A live single-use capability, never reconstructed from durable receipt history.
public protocol ExternalAdmissionAuthorizing: Sendable {
    func takeStart(_ actionID: String) async throws -> ExternalAdmission
}
