import Foundation
import FormalCompiler
import FormalCore
import FormalEvidence
import FormalValidation
import VerificationCore

public struct FormalBackend: VerificationBackend {
    private let runner: any ToolExecuting
    public init(runner: any ToolExecuting = LocalToolRunner()) { self.runner = runner }
    public static func supportsModelLanguage(_ name: String) -> Bool { SourceLanguage(rawValue: name) != nil }
    public func toolchainIdentity(at path: String) throws -> String {
        try PinnedToolchain().verify(at: URL(fileURLWithPath: path)).policy.inventorySHA256
    }
    public func prepare(source: Data,language name: String,executorIdentity: String,output: URL,budget: RunBudget) async throws -> PreparedFormalUnit {
        guard let language = SourceLanguage(rawValue: name), [.swift,.rust].contains(language) else { throw InvarError("UNSUPPORTED_LANGUAGE","Formal units require an exact recorded Swift/Rust scalar-file binding",exitCode: 3) }
        let artifact: CompilationArtifact
        do {
            artifact = try CompilationArtifactGenerator().generate(CompilationRequest(source: source,language: language,moduleID: "Source",evidenceBudget: Self.evidenceBudget(budget)))
        } catch let error as SourceDiagnostic { throw InvarError("UNSUPPORTED_SOURCE_PROFILE",error.description,exitCode: 3) }
        catch let error as FormalDiagnostic { throw InvarError(error.code.rawValue,error.message,exitCode: error.exitCode) }
        let reference = try await artifact.write(to: output)
        let bytes = try ArtifactJSON.readBytes(from: output.appendingPathComponent("compilation.json"),maximumBytes: 32768)
        let sourceDigest = Canonical.digest(source)
        let id = try PreparedFormalUnit.key(sourceDigest: sourceDigest,language: name,executorIdentity: executorIdentity)
        return PreparedFormalUnit(id: id,sourceDigest: sourceDigest,language: name,executorIdentity: executorIdentity,
            manifest: EvidenceArtifactReference(id: reference.sha256,sha256: reference.sha256,byteCount: bytes.count,mediaType: "application/json",profile: "formal-compilation/2"),
            evidence: EvidenceArtifactReference(id: reference.evidence.id,sha256: reference.evidence.sha256,byteCount: reference.evidence.byteCount,mediaType: "application/vnd.formal.evidence.sqlite",profile: "formal-evidence/1"))
    }
    public func execute(_ context: BackendContext) async throws -> VerificationEvidence {
        let started = Canonical.date()
        guard let check = context.job.formal, check.approved, let preparation = context.job.compilation, let artifact = context.compilationRoot else { throw InvarError("UNAPPROVED_OBLIGATION","Formal obligation lacks its approved prepared compilation",exitCode: 8) }
        let specification = try FixedInputReader.oracle(context)
        guard let file = context.job.inputs.first(where: { $0.path == check.source }) else { throw InvarError("INPUT_UNAVAILABLE","Formal source is not captured") }
        guard ["swift","rust"].contains(preparation.language), preparation.sourceDigest == file.digest, preparation.executorIdentity == context.executorIdentity else { throw InvarError("INPUT_MISMATCH","Prepared compilation differs from fixed source binding") }
        let source = try ArtifactJSON.readBytes(from: context.inputRoot.appendingPathComponent(check.source),maximumBytes: 1_000_000)
        let manifest = try ArtifactJSON.readBytes(from: artifact.appendingPathComponent("compilation.json"),maximumBytes: 32768)
        guard source.count == file.byteCount, Canonical.digest(source) == file.digest, Canonical.digest(manifest) == preparation.manifest.sha256 else { throw InvarError("INPUT_MISMATCH","Captured source/prepared manifest changed") }
        guard context.job.toolchainIdentity != nil else { throw InvarError("BLOCKED_TOOLCHAIN","Runtime unavailable at planning; explicitly prepare tools and create a new plan",exitCode: 3) }
        let tools = try PinnedToolchain().verify(at: URL(fileURLWithPath: check.toolchain))
        guard context.job.toolchainIdentity == tools.policy.inventorySHA256 else { throw InvarError("TOOLCHAIN_MISMATCH","Formal tools differ from the sealed plan") }
        let oracle = context.outputRoot.appendingPathComponent("oracle.json")
        try specification.write(to: oracle,options: .atomic)
        let output = context.outputRoot.appendingPathComponent("checked")
        let result: FormalVerificationResult
        if check.mode == "finite" {
            result = try await ModelVerifier(runner: runner).check(artifact: artifact,scenario: oracle,output: output,evidenceBudget: Self.evidenceBudget(context.budget),toolchain: tools,timeout: context.timeoutSeconds)
        } else {
            result = try await PropertyVerifier(runner: runner).check(artifact: artifact,properties: oracle,output: output,evidenceBudget: Self.evidenceBudget(context.budget),toolchain: tools,timeout: context.timeoutSeconds)
        }
        let report = try Canonical.encode(result)
        let scope = Set(result.claims.map(\.scope)).sorted().joined(separator: "; ")
        let outcome = result.exitCode == 0 ? "holdsWithinScope" : result.exitCode == 5 ? "violatedWithinScope" : "unknown"
        let execution = result.claims.allSatisfy({ $0.execution == "completed" }) ? "completed" : result.exitCode == 6 ? "resourceLimited" : "toolError"
        let resultArtifact = try EvidenceArtifactOutput.json(report,profile: "formal-verification/1",context: context)
        let manifestArtifact = try EvidenceArtifactOutput.json(manifest,profile: "formal-compilation/2",context: context)
        let oracleArtifact = try EvidenceArtifactOutput.json(specification,profile: result.specification.profile,context: context)
        let compiledBundle = try EvidenceArtifactOutput.bundle(root: artifact.appendingPathComponent("evidence"),id: result.compilationEvidence.id,sha256: result.compilationEvidence.sha256,byteCount: result.compilationEvidence.byteCount,context: context)
        let checkedBundle = try EvidenceArtifactOutput.bundle(root: output.appendingPathComponent("evidence"),id: result.evidence.id,sha256: result.evidence.sha256,byteCount: result.evidence.byteCount,context: context)
        return VerificationEvidence(inputID: context.input.id,jobID: context.job.id,execution: execution,outcome: outcome,domain: "generatedModel",translation: "unvalidated",scope: scope,adequacy: "completeWithinScope",detail: "Exact prepared generated-model obligations and structured formal evidence. Source-to-model correspondence remains UNVALIDATED.",assumptions: Array(Set(result.claims.flatMap(\.assumptions))).sorted(),artifacts: [resultArtifact,manifestArtifact,oracleArtifact,compiledBundle,checkedBundle],startedAt: started,finishedAt: Canonical.date())
    }
    private static func evidenceBudget(_ budget: RunBudget) -> EvidenceReadBudget {
        EvidenceReadBudget(maximumDatabaseBytes: budget.maximumWorkspaceBytes,maximumRecordBytes: min(262_144,budget.maximumOutputBytes),maximumPageBytes: budget.maximumOutputBytes,maximumNodes: 500,maximumEdges: 1500,maximumTraversalNodes: 100_000,maximumCursors: 64)
    }
}
