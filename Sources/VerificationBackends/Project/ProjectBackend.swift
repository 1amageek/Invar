import ArchitectureCore
import Foundation
import FormalValidation
import VerificationCore

/// Executes reviewed project code on an attempt-owned copy of sealed inputs.
public struct ProjectBackend: VerificationBackend {
    public init() {}
    public func execute(_ context: BackendContext) async throws -> VerificationEvidence {
        guard let check = context.job.project else { throw InvarError("POLICY_DENIED","Project execution requires a captured check") }
        try check.validate()
        if check.stage == .greenfieldSpecification {
            guard !context.job.inputs.contains(where: { ["swift", "rs"].contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased()) }) else {
                throw InvarError("GREENFIELD_SOURCE_PRESENT", "Greenfield Specification Verification requires a snapshot before production source files exist", exitCode: 8)
            }
        }
        let started = Canonical.date(), clock = ContinuousClock.now
        let work = context.outputRoot.appendingPathComponent("native"), root = work.appendingPathComponent("workspace")
        let manager = FileManager.default
        try manager.createDirectory(at: root,withIntermediateDirectories: true,attributes: [.posixPermissions:0o700])
        func tools() throws {
            for (path,digest) in check.toolDigests {
                let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.isRegularFileKey,.fileSizeKey])
                guard values.isRegularFile == true, let size = values.fileSize, size <= 256 * 1024 * 1024 else { throw InvarError("RESOURCE_LIMIT","Configured project tool exceeds its file bound",exitCode: 6) }
                let bytes = try Data(contentsOf: URL(fileURLWithPath: path),options: .mappedIfSafe)
                guard bytes.count <= 256 * 1024 * 1024, Canonical.digest(bytes) == digest else { throw InvarError("INPUT_MISMATCH","Configured project tool changed: " + path) }
            }
        }
        try tools()
        let toolPaths = check.toolDigests.keys.sorted()
        let sandbox = try ProjectSandbox.install(at: work,tools: toolPaths)
        for entry in context.job.inputs {
            try Task.checkCancellation()
            let bytes = try FixedInputReader.read(context.inputRoot.appendingPathComponent(entry.path),maximum: entry.byteCount)
            guard bytes.count == entry.byteCount, Canonical.digest(bytes) == entry.digest else { throw InvarError("INPUT_MISMATCH","Captured project input changed") }
            let target = root.appendingPathComponent(entry.path)
            try manager.createDirectory(at: target.deletingLastPathComponent(),withIntermediateDirectories: true,attributes: [.posixPermissions:0o700])
            try bytes.write(to: target,options: .withoutOverwriting)
        }
        var environment = ProcessInfo.processInfo.environment.filter { ["PATH","TOOLCHAINS","SDKROOT","DEVELOPER_DIR"].contains($0.key) }
        for key in ["HOME","TMPDIR"] {
            let directory = work.appendingPathComponent(key.lowercased())
            try manager.createDirectory(at: directory,withIntermediateDirectories: true,attributes: [.posixPermissions:0o700]); environment[key] = directory.path
        }
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        let journal = try ToolLaunchJournal(directory: context.outputRoot.appendingPathComponent("native-processes"),artifactRoot: work)
        var consumedCPU = 0.0
        func run(_ arguments: [String],name: String,profile: URL) async throws -> ToolResult {
            let elapsed = clock.duration(to: .now).components
            let remaining = context.timeoutSeconds - Double(elapsed.seconds) - Double(elapsed.attoseconds) / 1e18
            let cpu = context.budget.maximumCPUSeconds - consumedCPU
            guard remaining > 0, cpu > 0 else { throw InvarError("RESOURCE_LIMIT","Project execution budget exhausted",exitCode: 6) }
            let limits = ToolProcessLimits(maximumResidentBytes: UInt64(context.job.memoryMiB) * 1024 * 1024,maximumProcesses: context.budget.maximumProcesses,maximumCPUSeconds: cpu)
            let runner = LocalToolRunner(ownership: .isolatedSession,limits: limits,journal: journal,workspaceAccountingRoot: work)
            let invocation = ["-f",profile.path,check.command[0]] + arguments
            let result = try await runner.run(executable: ProjectSandbox.executable,arguments: invocation,directory: root,environment: environment,log: work.appendingPathComponent(name),timeout: remaining,maximumOutputBytes: context.budget.maximumOutputBytes,maximumWorkspaceBytes: context.budget.maximumWorkspaceBytes)
            consumedCPU += WorkerInvocation.measurements(result)["cpuSeconds",default:0]
            return result
        }
        var arguments = Array(check.command.dropFirst()); arguments[0] = root.appendingPathComponent(check.command[1]).path
        let result = try await run(arguments,name: "workflow",profile: sandbox)
        guard [0,5,6].contains(result.exitCode) else {
            throw InvarError("PROJECT_COMMAND_FAILED","Project workflow exited with status \(result.exitCode) before returning a report",exitCode: 7)
        }
        guard let summary = try JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String:Any],
            let manifest = summary["manifest"] as? String, summary["report"] as? String == check.report else { throw InvarError("INVALID_RESULT","Project workflow must return its receipt manifest and configured report") }
        _ = try Canonical.relative(manifest)
        guard manifest.hasPrefix(String(check.report.prefix(through: check.report.lastIndex(of: "/")!)) + "runs/") else { throw InvarError("INVALID_RESULT","Project receipt manifest is outside its retained run directory") }
        let validationRoot = work.appendingPathComponent("validation")
        try manager.createDirectory(at: validationRoot,withIntermediateDirectories: false,attributes: [.posixPermissions:0o700])
        let rebuilt = validationRoot.appendingPathComponent("validated-report.json")
        let validationProfile = try ProjectSandbox.install(at: work,tools: toolPaths,validating: true)
        let validation = try await run([check.reportBuilder,"--workspace",root.path,"--manifest",root.appendingPathComponent(manifest).path,"--output",rebuilt.path],name: "receipt-validation",profile: validationProfile)
        guard [0,5,6].contains(validation.exitCode) else { throw InvarError("INVALID_RESULT","Project receipt validation exited with status \(validation.exitCode)") }
        let report = try FixedInputReader.read(root.appendingPathComponent(check.report),maximum: context.budget.maximumOutputBytes)
        let validated = try FixedInputReader.read(rebuilt,maximum: context.budget.maximumOutputBytes)
        let originalJSON = try JSONSerialization.jsonObject(with: report) as? NSDictionary
        let validatedJSON = try JSONSerialization.jsonObject(with: validated) as? NSDictionary
        let document = try JSONDecoder().decode(JSONValue.self, from: validated)
        let verificationReport = document["metadata"]["verificationReport"]
        if check.stage == .greenfieldSpecification {
            guard verificationReport["workflow"]["productionInputCount"].int == 0 else {
                throw InvarError("INVALID_RESULT", "A greenfield specification report must have an empty production inventory")
            }
        }
        let outcome = try ProjectReportAssessment.outcome(validated)
        let capturedDigests = Dictionary(uniqueKeysWithValues: context.job.inputs.map { ($0.path, $0.digest) })
        for reference in verificationReport["architectureInputs"].array {
            guard let path = reference["path"].string, let digest = reference["sha256"].string, capturedDigests[path] == digest else {
                throw InvarError("INPUT_MISMATCH", "Architecture declarations must belong to the captured workspace")
            }
        }
        let expected: Int32 = outcome == "passed" ? 0 : outcome == "failed" ? 5 : 6
        guard originalJSON != nil, originalJSON == validatedJSON, result.exitCode == expected, validation.exitCode == expected else { throw InvarError("INVALID_RESULT","Project report, receipts and process exit disagree") }
        for entry in context.job.inputs {
            let bytes = try FixedInputReader.read(root.appendingPathComponent(entry.path),maximum: entry.byteCount)
            guard Canonical.digest(bytes) == entry.digest else { throw InvarError("INPUT_MISMATCH","Project workflow modified a verification input") }
        }
        try tools()
        let archiveBytes = try ProjectEvidenceArchive.encode(root: root,manifest: manifest,check: check,maximumBytes: context.budget.maximumOutputBytes)
        let archive = try EvidenceArtifactOutput.json(archiveBytes,profile: "project-evidence/1",context: context)
        let artifact = try EvidenceArtifactOutput.json(validated,profile: "project-report/1",context: context)
        return VerificationEvidence(inputID: context.input.id,jobID: context.job.id,execution: "completed",outcome: outcome == "passed" ? "holdsWithinScope" : outcome == "failed" ? "violatedWithinScope" : "unknown",domain: "projectContract",translation: "notApplicable",scope: "Complete acceptance inventory across specification, production implementation and correspondence",adequacy: outcome == "passed" ? "completeWithinScope" : "unknown",detail: "Project verification " + outcome,assumptions: ["Configured workflow and report builder; per-requirement scope and correspondence remain in the report."],artifacts: [artifact,archive],resources: ["cpuSeconds":consumedCPU],startedAt: started,finishedAt: Canonical.date())
    }
}
