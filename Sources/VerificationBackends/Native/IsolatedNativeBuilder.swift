import Foundation
import VerificationCore

struct IsolatedNativeBuilder: NativeBuildPreparing {
    let executable: URL
    func prepare(_ context: BackendContext) async throws -> NativeBuildArtifact {
        let result = try await WorkerInvocation(executable: executable).run("native-build", context: context)
        let bytes = Data(result.standardOutput.utf8)
        let value = try JSONDecoder().decode(NativeBuildArtifact.self, from: bytes)
        return NativeBuildArtifact(planID: value.planID, jobID: value.jobID, binary: value.binary, binaryDigest: value.binaryDigest, environmentIdentity: value.environmentIdentity, resources: WorkerInvocation.measurements(result))
    }
    func verifyEnvironment(_ context: BackendContext, identity: String) async throws -> [String: Double] {
        let result = try await WorkerInvocation(executable: executable).run("native-verify", context: context)
        let bytes = Data(result.standardOutput.utf8)
        let value = try JSONDecoder().decode([String: String].self, from: bytes)
        guard value["identity"] == identity else { throw InvarError("TOOLCHAIN_MISMATCH", "Native postflight environment differs") }
        return WorkerInvocation.measurements(result)
    }
}
