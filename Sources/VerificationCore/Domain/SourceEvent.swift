public struct SourceEvent: Sendable, Equatable {
    public let epoch: String
    public let snapshotID: String?
    public let sequence: Int?
    public let ready: Bool
    public let invalidated: Bool
    public let continuityLost: Bool
    public let reason: String?
    public init(epoch: String,snapshotID: String?,sequence: Int?,ready: Bool,invalidated: Bool,continuityLost: Bool,reason: String?) {
        self.epoch = epoch; self.snapshotID = snapshotID; self.sequence = sequence; self.ready = ready
        self.invalidated = invalidated; self.continuityLost = continuityLost; self.reason = reason
    }
}
