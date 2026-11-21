import ArchitectureClient
import VerificationCore

public protocol ExplorerConnecting: ArchitectureReading {
    func start() async throws -> ExplorerConnectionStatus
    func status() async -> ExplorerConnectionStatus
    func provider() async throws -> ExtensionProviderClient
    func closeAdmission() async
    func shutdown() async throws
}
