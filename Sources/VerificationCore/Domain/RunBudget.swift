import Foundation

public struct RunBudget: Codable, Sendable, Equatable {
    public let maximumWorkers: Int
    public let memoryMiB: Int
    public let runTimeoutSeconds: Double
    public let timeoutSeconds: Double
    public let maximumProcesses: Int
    public let maximumCPUSeconds: Double
    public let maximumWorkspaceBytes: Int
    public let maximumOutputBytes: Int
    public init(maximumWorkers: Int = 2, memoryMiB: Int = 4096, timeoutSeconds: Double = 120, runTimeoutSeconds: Double = 300, maximumOutputBytes: Int = 8388608, maximumProcesses: Int = 8, maximumCPUSeconds: Double = 120, maximumWorkspaceBytes: Int = 536870912) {
        self.maximumWorkers = maximumWorkers
        self.memoryMiB = memoryMiB
        self.timeoutSeconds = timeoutSeconds
        self.runTimeoutSeconds = runTimeoutSeconds
        self.maximumProcesses = maximumProcesses
        self.maximumCPUSeconds = maximumCPUSeconds
        self.maximumWorkspaceBytes = maximumWorkspaceBytes
        self.maximumOutputBytes = maximumOutputBytes
    }
}
