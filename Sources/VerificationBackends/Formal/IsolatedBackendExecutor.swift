import Foundation
import FormalCore
import FormalValidation
import VerificationCore

public struct IsolatedBackendExecutor: VerificationBackend {
    private let executable: URL
    public init(executable: URL) { self.executable = executable }
    public func execute(_ context: BackendContext) async throws -> VerificationEvidence {
        do {
            if context.job.backend == "project" { return try await ProjectBackend().execute(context) }
            if ["native", "fuzz"].contains(context.job.backend) {
                guard context.nativeExecutionAllowed else { throw InvarError("POLICY_DENIED", "Host did not authorize native execution", exitCode: 8) }
                let runner = try NativeSessionExecutor(context: context)
                let backend = NativeBackend(builder: IsolatedNativeBuilder(executable: executable), runner: runner)
                return try await backend.execute(context)
            }
            let result = try await WorkerInvocation(executable: executable).run("worker", context: context)
            let data = Data(result.standardOutput.utf8)
            let value = try JSONDecoder().decode(VerificationEvidence.self, from: data)
            guard value.jobID == context.job.id else { throw InvarError("INVALID_RESULT", "Worker result belongs to another job") }
            return value.measuring(WorkerInvocation.measurements(result))
        } catch let error as ToolResourceLimit { throw InvarError("RESOURCE_LIMIT", error.description, exitCode: 6) }
        catch let error as FormalDiagnostic { throw InvarError(error.code.rawValue, error.message, exitCode: error.exitCode) }
    }
}
