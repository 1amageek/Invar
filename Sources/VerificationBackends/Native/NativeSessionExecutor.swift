import Darwin
import Foundation
import FormalValidation
import VerificationCore

public actor NativeSessionExecutor: NativeSessionExecuting {
    private let context: BackendContext
    private let journal: ToolLaunchJournal
    private let started = ContinuousClock.now
    private let initialCoordinatorCPU: Double
    private var toolCPU = 0.0
    private var peakResident = 0.0
    private var peakProcesses = 0.0
    public init(context: BackendContext) throws {
        self.context = context
        journal = try ToolLaunchJournal(directory: context.outputRoot.appendingPathComponent("native-processes"), artifactRoot: context.outputRoot.appendingPathComponent("native"))
        initialCoordinatorCPU = try Self.coordinatorCPU()
    }
    public func charge(_ resources: [String: Double]) throws {
        guard let cpu = resources["cpuSeconds"], cpu >= 0, cpu.isFinite else { throw InvarError("UNKNOWN_RESOURCE_USAGE", "Native phase has no valid CPU accounting", exitCode: 6) }
        toolCPU += cpu
        peakResident = max(peakResident, resources["sampledPeakResidentBytes", default: 0])
        peakProcesses = max(peakProcesses, resources["sampledPeakProcesses", default: 0])
        _ = try remainingCPU()
    }
    public func run(executable: URL, arguments: [String], directory: URL, environment: [String: String], log: URL, timeout: Double, maximumOutputBytes: Int, maximumWorkspaceBytes: Int?) async throws -> ToolResult {
        let work = context.outputRoot.appendingPathComponent("native")
        guard executable.path == "/usr/bin/sandbox-exec", arguments.count >= 3, Array(arguments.prefix(3)) == ["-f", work.appendingPathComponent("run.sb").path, work.appendingPathComponent("harness").path], directory.path == work.path else { throw InvarError("POLICY_DENIED", "Native invocation exceeds its fixed profile", exitCode: 8) }
        let remaining = try remainingCPU()
        let limits = ToolProcessLimits(maximumResidentBytes: UInt64(context.job.memoryMiB) * 1024 * 1024, maximumProcesses: context.budget.maximumProcesses, maximumCPUSeconds: remaining)
        let runner = LocalToolRunner(ownership: .isolatedSession, limits: limits, journal: journal)
        let result = try await runner.run(executable: executable, arguments: arguments, directory: directory, environment: environment, log: log, timeout: timeout, maximumOutputBytes: maximumOutputBytes, maximumWorkspaceBytes: maximumWorkspaceBytes)
        try charge(WorkerInvocation.measurements(result)); return result
    }
    public func summary() throws -> [String: Double] {
        let duration = started.duration(to: .now).components
        let coordinator = max(0, try Self.coordinatorCPU() - initialCoordinatorCPU)
        _ = try remainingCPU()
        return ["wallSeconds": Double(duration.seconds) + Double(duration.attoseconds) / 1e18, "cpuSeconds": toolCPU + coordinator, "toolCPUSeconds": toolCPU,
            "coordinatorCPUUpperBoundSeconds": coordinator, "sampledPeakResidentBytes": peakResident, "sampledPeakProcesses": peakProcesses, "samplingIntervalSeconds": 0.025]
    }
    private func remainingCPU() throws -> Double {
        let coordinator = max(0, try Self.coordinatorCPU() - initialCoordinatorCPU)
        let remaining = context.budget.maximumCPUSeconds - toolCPU - coordinator
        guard remaining > 0 else { throw InvarError("RESOURCE_LIMIT", "Native attempt exceeded cumulative CPU budget", exitCode: 6) }
        return remaining
    }
    private static func coordinatorCPU() throws -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw InvarError("UNKNOWN_RESOURCE_USAGE", "Cannot inspect coordinator CPU", exitCode: 6) }
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
}
