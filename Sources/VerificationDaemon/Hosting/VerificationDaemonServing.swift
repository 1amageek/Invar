public protocol VerificationDaemonServing: Sendable {
    func serve(_ configuration: DaemonConfiguration) async throws
}
