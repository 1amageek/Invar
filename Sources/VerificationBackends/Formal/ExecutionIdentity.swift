import Foundation
import FormalCompiler
import FormalCore
import FormalValidation
import VerificationCore

public enum ExecutionIdentity {
    public static func current(executable: URL) throws -> String {
        let values = try executable.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 256 * 1024 * 1024 else { throw InvarError("EXECUTOR_UNAVAILABLE", "Executor binary exceeds its identity budget") }
        // The OS owns the mapped bytes through this invocation; hash once at the identity boundary.
        let binary = try Data(contentsOf: executable, options: .mappedIfSafe)
        let compilerResources = try CompilationArtifactGenerator.resourceIdentity()
        let validationResources = try ToolchainPolicy.resourceIdentity()
        let identity = ["executor": Canonical.digest(binary), "compilerResources": compilerResources, "validationResources": validationResources]
        return try Canonical.identity(identity)
    }
}
