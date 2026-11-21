public struct SchedulingStatus: Sendable, Equatable {
    public let activeExecutions: Int
    public let waitingExecutions: Int
    public let interests: Int
    public let reservedMemoryMiB: Int
    public let reservedProcesses: Int
    public let reservedScratchBytes: Int
    public init(activeExecutions: Int,waitingExecutions: Int,interests: Int,reservedMemoryMiB: Int,reservedProcesses: Int,reservedScratchBytes: Int) {
        self.activeExecutions = activeExecutions; self.waitingExecutions = waitingExecutions; self.interests = interests
        self.reservedMemoryMiB = reservedMemoryMiB; self.reservedProcesses = reservedProcesses; self.reservedScratchBytes = reservedScratchBytes
    }
}
