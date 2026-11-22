import Foundation
import FormalCore
import FormalValidation
import VerificationCore

public struct NativeBackend: VerificationBackend {
    private let builder: any NativeBuildPreparing
    private let runner: any NativeSessionExecuting
    public init(builder: any NativeBuildPreparing, runner: any NativeSessionExecuting) { self.builder = builder; self.runner = runner }
    public func execute(_ context: BackendContext) async throws -> VerificationEvidence {
        let started = Canonical.date()
        guard let profile = context.job.native?.profile ?? context.job.fuzz?.profile else { throw InvarError("POLICY_DENIED", "Native execution lacks its profile", exitCode: 8) }
        let artifact = try await builder.prepare(context)
        try await runner.charge(artifact.resources)
        let work = context.outputRoot.appendingPathComponent("native")
        guard artifact.planID == context.planID, artifact.jobID == context.job.id, artifact.binary.standardizedFileURL.path == work.appendingPathComponent("harness").standardizedFileURL.path else { throw InvarError("INVALID_RESULT", "Native build artifact differs from the job") }
        let binaryData = try ArtifactJSON.readBytes(from: artifact.binary, maximumBytes: 64 * 1024 * 1024)
        guard Canonical.digest(binaryData) == artifact.binaryDigest else { throw InvarError("INPUT_MISMATCH", "Native binary changed before execution") }
        let binaryDigest = artifact.binaryDigest, initialTools = artifact.environmentIdentity
        let result: VerificationEvidence
        if let check = context.job.native {
            let observation = try await observe(arguments: [], expectedCount: check.expectedTestCount, expectedSignal: check.expectedSignal, profile: profile, context: context, work: work, label: "test")
            let observationBytes = try Canonical.encode(observation)
            let report = try Canonical.encode(["profile": profile.kind, "binaryDigest": binaryDigest, "environmentIdentity": initialTools, "observation": String(decoding: observationBytes, as: UTF8.self)])
            let reproductionKey = try Canonical.identity(["classification": observation.classification, "count": String(observation.testsRun)])
            let reportArtifact = try EvidenceArtifactOutput.json(report,profile: "native-observation/1",context: context)
            result = VerificationEvidence(inputID: context.input.id,jobID: check.id, execution: "completed", outcome: observation.outcome, domain: "nativeExecution", translation: "notApplicable", scope: "EXPLICIT_NATIVE_HARNESS_TESTS", adequacy: "completeWithinScope", detail: "Original captured modules executed with the approved harness oracle; observed count/classification retained privately.", artifacts: [reportArtifact], diagnosticCode: observation.classification, startedAt: started, finishedAt: Canonical.date(), reproductionKey: reproductionKey)
        } else if let check = context.job.fuzz {
            result = try await fuzz(check, binaryDigest: binaryDigest, environment: initialTools, context: context, work: work, started: started)
        } else { throw InvarError("INVALID_PLAN", "Missing native/fuzz obligation") }
        let postflight = try await builder.verifyEnvironment(context, identity: initialTools)
        try await runner.charge(postflight)
        let resources = try await runner.summary()
        return result.measuring(resources)
    }
    private func invoke(arguments: [String], context: BackendContext, work: URL, label: String) async throws -> ToolResult {
        let scratch = work.appendingPathComponent("runtime"), temporary = scratch.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        return try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"), arguments: ["-f", work.appendingPathComponent("run.sb").path, work.appendingPathComponent("harness").path] + arguments,
            directory: work, environment: ["PATH": "/usr/bin:/bin", "HOME": scratch.path, "TMPDIR": temporary.path, "LANG": "C", "LC_ALL": "C"],
            log: scratch.appendingPathComponent(label), timeout: context.timeoutSeconds, maximumOutputBytes: context.budget.maximumOutputBytes, maximumWorkspaceBytes: context.budget.maximumWorkspaceBytes)
    }
    private func observe(arguments: [String], expectedCount: Int, expectedSignal: Int32? = nil, profile: NativeProfile, context: BackendContext, work: URL, label: String) async throws -> NativeObservation {
        let value = try await invoke(arguments: arguments, context: context, work: work, label: label)
        let stdout = Canonical.digest(Data(value.standardOutput.utf8)), stderr = Canonical.digest(Data(value.standardError.utf8))
        if let signal = expectedSignal, value.exitCode == 128 + signal { return NativeObservation(outcome: "holdsWithinScope", classification: "EXPECTED_SIGNAL_" + String(signal), exitCode: value.exitCode, testsRun: 1, stdoutDigest: stdout, stderrDigest: stderr) }
        if value.exitCode >= 128 { return NativeObservation(outcome: "violatedWithinScope", classification: "UNEXPECTED_SIGNAL_" + String(value.exitCode - 128), exitCode: value.exitCode, testsRun: 0, stdoutDigest: stdout, stderrDigest: stderr) }
        guard value.exitCode == 0 else { throw InvarError("NATIVE_RUNNER_ERROR", "Native harness returned a nonzero exit without a valid oracle report", exitCode: 7) }
        guard expectedSignal == nil else { return NativeObservation(outcome: "violatedWithinScope", classification: "EXPECTED_SIGNAL_NOT_OBSERVED", exitCode: value.exitCode, testsRun: 0, stdoutDigest: stdout, stderrDigest: stderr) }
        let bytes = Data(value.standardOutput.utf8)
        guard bytes.count <= 32768 else { throw InvarError("INVALID_NATIVE_ORACLE", "Native oracle exceeds its bound", exitCode: 7) }
        let oracle: NativeOracleReport
        do {
            let raw = try JSONSerialization.jsonObject(with: bytes)
            guard let object = raw as? [String: Any], Set(object.keys) == ["schemaVersion", "testsRun", "holds"] else { throw InvarError("INVALID_NATIVE_ORACLE", "Native oracle fields are invalid", exitCode: 7) }
            oracle = try JSONDecoder().decode(NativeOracleReport.self, from: bytes)
        } catch { throw InvarError("INVALID_NATIVE_ORACLE", "Native oracle is not a valid versioned report", exitCode: 7) }
        guard oracle.schemaVersion == 1, oracle.testsRun == expectedCount, expectedCount > 0 else { throw InvarError("INVALID_NATIVE_ORACLE", "Native oracle is malformed, empty or skipped expected tests", exitCode: 7) }
        let holds = oracle.holds
        return NativeObservation(outcome: holds ? "holdsWithinScope" : "violatedWithinScope", classification: holds ? "NATIVE_TESTS_PASSED" : "ORACLE_FALSE", exitCode: value.exitCode, testsRun: expectedCount, stdoutDigest: stdout, stderrDigest: stderr)
    }
    private func fuzz(_ check: FuzzCheck, binaryDigest: String, environment: String, context: BackendContext, work: URL, started: String) async throws -> VerificationEvidence {
        let bytes = try FixedInputReader.oracle(context)
        let corpus = try JSONDecoder().decode([String].self, from: bytes)
        guard corpus.count <= 1000, corpus.allSatisfy({ Int64($0) != nil }), let lower = Int64(check.minimum), let upper = Int64(check.maximum), corpus.allSatisfy({ Int64($0).map { lower <= $0 && $0 <= upper } == true }) else { throw InvarError("INVALID_CONFIGURATION", "Fuzz corpus is outside the declared signed domain", exitCode: 2) }
        var generator = try SeededSignedInputs(check), executed = 0, witness: String?, reduced: String?, classification: String?
        for index in 0..<(corpus.count + check.iterations) {
            try Task.checkCancellation()
            let input = index < corpus.count ? corpus[index] : generator.next()
            let value = try await observe(arguments: [input], expectedCount: 1, profile: check.profile, context: context, work: work, label: "sample-" + String(index))
            executed += 1
            if value.outcome == "violatedWithinScope" { witness = input; reduced = input; classification = value.classification; break }
        }
        if let original = witness, let initial = Int64(original), let classification {
            var current = initial
            for index in 0..<32 {
                let half = current / 2, candidate = index == 0 ? 0 : index % 2 == 1 ? half : current > 0 ? current - 1 : current < 0 ? current + 1 : 0
                if candidate == current || candidate < lower || candidate > upper { continue }
                let value = try await observe(arguments: [String(candidate)], expectedCount: 1, profile: check.profile, context: context, work: work, label: "shrink-" + String(index))
                if value.outcome == "violatedWithinScope" && value.classification == classification { current = candidate; reduced = String(candidate) }
            }
        }
        let report = try Canonical.encode(["profile": "seeded-signed64/1", "binaryDigest": binaryDigest, "environmentIdentity": environment, "corpusDigest": Canonical.digest(bytes), "seed": check.seed, "encoding": check.inputEncoding, "minimum": check.minimum, "maximum": check.maximum, "executed": String(executed), "originalInput": witness ?? "none", "reducedInput": reduced ?? "none", "classification": classification ?? "NO_VIOLATION_OBSERVED"])
        let reproductionKey: String?
        if let witness, let classification { reproductionKey = try Canonical.identity(["encoding": check.inputEncoding, "input": witness, "classification": classification]) } else { reproductionKey = nil }
        let artifact = try EvidenceArtifactOutput.json(report,profile: "native-fuzz/1",context: context)
        return VerificationEvidence(inputID: context.input.id,jobID: check.id, execution: "completed", outcome: witness == nil ? "noViolationObservedWithinBudget" : "violatedWithinScope", domain: "nativeExecution", translation: "notApplicable", scope: "BOUNDED_SEEDED_NATIVE_INPUTS", adequacy: "completeWithinScope", detail: "Explicit harness/corpus/seeded signed64 samples. No coverage-guided or universal guarantee. Original and checked reduced witness retained separately.", artifacts: [artifact], diagnosticCode: classification ?? "NO_VIOLATION_OBSERVED", startedAt: started, finishedAt: Canonical.date(), reproductionKey: reproductionKey)
    }
}
