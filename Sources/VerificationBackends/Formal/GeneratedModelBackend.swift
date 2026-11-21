import Foundation
import FormalCore
import FormalCompiler
import FormalEvidence
import VerificationCore

/// Generates diagrams from the emitter's own indexed program documents.
struct GeneratedModelBackend: VerificationBackend {
    func execute(_ context: BackendContext) async throws -> VerificationEvidence {
        let started = Canonical.date()
        guard let entity = context.job.modelSource, let file = context.job.inputs.first,
            let language = SourceLanguage(rawValue: entity.language) else {
            throw InvarError("INVALID_PLAN","Missing model source")
        }
        let full = try FixedInputReader.read(context.inputRoot.appendingPathComponent(file.path),maximum: min(file.byteCount,1_000_000))
        guard full.count == file.byteCount, Canonical.digest(full) == file.digest else { throw InvarError("INPUT_MISMATCH","Model source changed") }
        let source: Data, scope: String, selectedRange: Range<Int>
        if entity.kind == "file" { source = full; scope = file.path; selectedRange = 0..<full.count }
        else {
            guard let start = entity.startByte, let end = entity.endByte, start >= 0, start < end, end <= full.count else {
                throw InvarError("INPUT_MISMATCH","Missing selected declaration range")
            }
            selectedRange = start..<end
            source = full.subdata(in: selectedRange)
            scope = "\(file.path) UTF-8 bytes \(start)..<\(end)"
        }
        let budget = EvidenceReadBudget(maximumDatabaseBytes: context.budget.maximumWorkspaceBytes,maximumRecordBytes: 262144,
            maximumPageBytes: context.budget.maximumOutputBytes,maximumNodes: 500,maximumEdges: 1500,maximumTraversalNodes: 4096,maximumCursors: 1)
        let root = context.outputRoot.appendingPathComponent("model")
        let bundle: EvidenceBundleReference
        let assumptions: [String]
        let detail: String
        let artifact: CompilationArtifact?
        do {
            artifact = try CompilationArtifactGenerator().generate(CompilationRequest(source: source,language: language,moduleID: "Source",evidenceBudget: budget))
        } catch is SourceDiagnostic where language == .swift {
            artifact = nil
        } catch let error as FormalDiagnostic where language == .swift && error.code == .unsupportedSourceProfile {
            artifact = nil
        }
        if let artifact {
            guard entity.kind == "file" || artifact.metadata.functions == [entity.name] else { throw InvarError("INPUT_MISMATCH","Emitted function differs from selected node") }
            bundle = try await artifact.writeGeneratedModels(to: root)
            assumptions = artifact.metadata.assumptions
            detail = "Model generated. No verification conditions were checked."
        } else {
            let sites = try SwiftExpressionSelection.extract(full, path: file.path, selection: selectedRange)
            bundle = try await SwiftExpressionModels.write(source: full, sites: sites, to: root, budget: budget)
            assumptions = ["Standard signed 64-bit integer operators and nonnegative collection counts. Each site is independent. Predicates are abstract inputs."]
            detail = "Partial model: \(sites.count) source sites. Arithmetic trap checks only. Framework calls, rendering and surrounding behavior are outside scope."
        }
        let stored = try EvidenceArtifactOutput.bundle(root: root,id: bundle.id,sha256: bundle.sha256,byteCount: bundle.byteCount,context: context)
        return VerificationEvidence(inputID: context.input.id,jobID: context.job.id,execution: "completed",outcome: "notEvaluated",domain: "generatedModel",translation: "unvalidated",scope: scope,adequacy: "unknown",detail: detail,assumptions: assumptions,artifacts: [stored],startedAt: started,finishedAt: Canonical.date())
    }
}
