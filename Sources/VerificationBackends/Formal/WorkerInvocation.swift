import Foundation
import FormalValidation
import VerificationCore

struct WorkerInvocation {
    let executable: URL
    func run(_ mode: String, context: BackendContext) async throws -> ToolResult {
        guard ["worker", "native-build", "native-verify"].contains(mode) else { throw InvarError("INVALID_ARGUMENT", "Invalid worker mode", exitCode: 2) }
        let request = context.outputRoot.appendingPathComponent(mode + "-request.json")
        let bytes = try Canonical.encode(context)
        guard bytes.count <= 1024 * 1024 else { throw InvarError("RESOURCE_LIMIT", "Worker request exceeds 1 MiB", exitCode: 6) }
        try bytes.write(to: request, options: .atomic)
        let limits = ToolProcessLimits(maximumResidentBytes: UInt64(context.job.memoryMiB) * 1024 * 1024, maximumProcesses: context.budget.maximumProcesses, maximumCPUSeconds: context.budget.maximumCPUSeconds)
        let value = try await LocalToolRunner(limits: limits).run(executable: executable, arguments: ["--internal-" + mode, request.path], directory: context.outputRoot,
            environment: ["PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C"], log: context.outputRoot.appendingPathComponent(mode), timeout: context.timeoutSeconds,
            maximumOutputBytes: context.budget.maximumOutputBytes, maximumWorkspaceBytes: context.budget.maximumWorkspaceBytes)
        if value.exitCode != 0 { let bytes = Data(value.standardOutput.utf8); let error = try JSONDecoder().decode(InvarError.self, from: bytes); throw error }
        return value
    }
    static func measurements(_ result: ToolResult) -> [String: Double] {
        ["wallSeconds": result.elapsedSeconds, "sampledPeakResidentBytes": Double(result.measurements.sampledPeakResidentBytes), "sampledPeakProcesses": Double(result.measurements.sampledPeakProcesses), "cpuSeconds": result.measurements.cpuSeconds, "samplingIntervalSeconds": 0.025]
    }
}
