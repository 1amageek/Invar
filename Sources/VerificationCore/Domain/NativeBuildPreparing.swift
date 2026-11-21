import Foundation

public protocol NativeBuildPreparing: Sendable {
    func prepare(_ context: BackendContext) async throws -> NativeBuildArtifact
    func verifyEnvironment(_ context: BackendContext, identity: String) async throws -> [String: Double]
}
