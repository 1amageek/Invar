public struct WatchCycle: Codable, Sendable, Equatable {
    public let generation: Int
    public let phase: String
    public let pendingDemandID: String?
    public let planID: String?
    public init(generation: Int = 0,phase: String = "idle",pendingDemandID: String? = nil,planID: String? = nil) {
        self.generation = generation; self.phase = phase; self.pendingDemandID = pendingDemandID; self.planID = planID
    }
}
