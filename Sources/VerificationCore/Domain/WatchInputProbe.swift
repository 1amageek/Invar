public struct WatchInputProbe: Sendable, Equatable {
    public let changed: Bool
    public let reason: String?
    public init(changed: Bool,reason: String?) { self.changed = changed; self.reason = reason }
}
