import FormalCompiler
import FormalCore
import VerificationCore

public struct BackendRouter: VerificationBackend {
    private let architecture: any VerificationBackend
    private let native: (any VerificationBackend)?
    private let formal: any VerificationBackend
    public init(architecture: any VerificationBackend, formal: any VerificationBackend, native: (any VerificationBackend)? = nil) { self.native = native; self.architecture = architecture; self.formal = formal }
    public func execute(_ context: BackendContext) async throws -> VerificationEvidence {
        do { switch context.job.backend {
        case "static": return try await architecture.execute(context)
        case "modelGeneration": return try await GeneratedModelBackend().execute(context)
        case "formal": return try await formal.execute(context)
        case "native", "fuzz": guard let native else { throw InvarError("UNSUPPORTED_BACKEND", "Native execution requires an isolated-session owner", exitCode: 3) }; return try await native.execute(context)
        default: throw InvarError("UNSUPPORTED_BACKEND", "Backend is not available: \(context.job.backend)", exitCode: 3)
        } } catch let error as FormalDiagnostic { throw InvarError(error.code.rawValue, error.message, exitCode: error.exitCode) }
        catch let error as SourceDiagnostic { throw InvarError("UNSUPPORTED_SOURCE_PROFILE", error.description, exitCode: 3) }
    }
}
