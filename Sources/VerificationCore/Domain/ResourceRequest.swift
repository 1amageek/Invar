public struct ResourceRequest: Sendable, Equatable {
    public let id: String
    public let memoryMiB: Int
    public let processes: Int
    public let scratchBytes: Int
    public let priority: Int
    public init(id: String,memoryMiB: Int,processes: Int,scratchBytes: Int,priority: Int) {
        self.id = id; self.memoryMiB = memoryMiB; self.processes = processes; self.scratchBytes = scratchBytes; self.priority = priority
    }
}
