public protocol SourceEventReading: Sendable {
    func poll() async throws -> SourceEvent
}
