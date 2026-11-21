import Foundation
import FormalValidation
import VerificationBackends
import VerificationCore
import VerificationDiscovery
import VerificationRuntime

struct WorkerCommand {
    static func execute(mode: String, input: String) async throws -> Data {
        let path = URL(fileURLWithPath: input)
        let values = try path.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 1024 * 1024 else { throw InvarError("INVALID_INPUT", "Invalid worker request") }
        let request = try Data(contentsOf: path), context = try JSONDecoder().decode(BackendContext.self, from: request)
        try PlanValidation.descriptor(context.descriptor)
        let descriptorID = try context.descriptor.identity()
        guard descriptorID == context.descriptorID else { throw InvarError("INPUT_MISMATCH","Worker descriptor checksum differs") }
        let executable = try InvarApp.executableURL()
        let identity = try ExecutionIdentity.current(executable: executable)
        guard identity == context.executorIdentity else { throw InvarError("EXECUTOR_MISMATCH", "Worker differs from the sealed plan") }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL.resolvingSymlinksInPath()
        guard context.outputRoot.standardizedFileURL.resolvingSymlinksInPath().path == cwd.path else { throw InvarError("INVALID_PLAN", "Worker directory differs") }
        return try await WorkerLifetime.supervise(output: context.outputRoot, parentPID: context.ownerPID) {
            let runner = LocalToolRunner(ownership: .inherited)
            switch mode {
            case "--internal-native-build":
                let artifact = try await NativeBuildService(runner: runner).prepare(context)
                return try Canonical.encode(artifact)
            case "--internal-native-verify":
                guard let expected = context.job.toolchainIdentity else { throw InvarError("BLOCKED_NATIVE_TOOLCHAIN", "No pinned native environment", exitCode: 3) }
                _ = try await NativeBuildService(runner: runner).verifyEnvironment(context, identity: expected)
                return try Canonical.encode(["identity": expected])
            case "--internal-worker":
                let router = BackendRouter(architecture: StaticBackend(evaluator: ArchitectureRuleEvaluator()), formal: FormalBackend(runner: runner))
                let value = try await router.execute(context)
                return try Canonical.encode(value)
            default: throw InvarError("INVALID_ARGUMENT", "Unknown worker mode", exitCode: 2)
            }
        }
    }
}
