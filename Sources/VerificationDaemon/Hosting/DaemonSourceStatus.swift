public struct DaemonSourceStatus: Sendable, Equatable {
    public let readiness: DaemonSourceReadiness
    public let diagnostics: [String]
    public init(_ readiness: DaemonSourceReadiness,diagnostics: [String] = []) { self.readiness = readiness; self.diagnostics = diagnostics }
}
