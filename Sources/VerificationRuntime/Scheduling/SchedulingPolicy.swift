import Foundation
import VerificationCore

public struct SchedulingPolicy: Sendable, Equatable {
    public let maximumWorkers: Int
    public let memoryMiB: Int
    public let maximumProcesses: Int
    public let maximumScratchBytes: Int
    public let maximumReadyJobs: Int
    public let maximumScratchFiles: Int
    public let maximumPriorityBypasses: Int
    public init(maximumWorkers: Int,memoryMiB: Int,maximumProcesses: Int,maximumScratchBytes: Int,maximumReadyJobs: Int,maximumScratchFiles: Int,maximumPriorityBypasses: Int) {
        self.maximumWorkers = maximumWorkers; self.memoryMiB = memoryMiB; self.maximumProcesses = maximumProcesses
        self.maximumScratchBytes = maximumScratchBytes; self.maximumReadyJobs = maximumReadyJobs
        self.maximumScratchFiles = maximumScratchFiles; self.maximumPriorityBypasses = maximumPriorityBypasses
    }
    // Capacity derives from two existing 4 GiB/8-process/512 MiB worker profiles;
    // one additional partition retains controller/index/history files in Store.
    public static let development = SchedulingPolicy(maximumWorkers: 2,memoryMiB: 8192,maximumProcesses: 16,maximumScratchBytes: 2 * 536_870_912,maximumReadyJobs: 64,maximumScratchFiles: StorePolicy.development.maximumFiles / 3,maximumPriorityBypasses: 64)
    public func validate() throws {
        guard (1...32).contains(maximumWorkers), memoryMiB > 0, maximumProcesses > 0, maximumScratchBytes > 0, maximumReadyJobs > 0, maximumScratchFiles > 0, maximumPriorityBypasses > 0 else { throw InvarError("INVALID_POLICY","Invalid shared scheduler policy") }
    }
}
