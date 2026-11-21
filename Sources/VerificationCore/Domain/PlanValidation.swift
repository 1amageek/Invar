import Foundation

public enum PlanValidation {
    public static func identifier(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= 128, value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { throw InvarError("INVALID_IDENTIFIER", "Unsafe stored/job identity", exitCode: 2) }
    }
    public static func budget(_ value: RunBudget) throws {
        guard (1...64).contains(value.maximumProcesses), value.maximumCPUSeconds.isFinite, (1...86400).contains(value.maximumCPUSeconds), (1048576...10737418240).contains(value.maximumWorkspaceBytes), (1...32).contains(value.maximumWorkers), (64...131072).contains(value.memoryMiB),
            value.timeoutSeconds.isFinite, (1...3600).contains(value.timeoutSeconds), value.runTimeoutSeconds.isFinite,
            (1...3600).contains(value.runTimeoutSeconds), (1024...16777216).contains(value.maximumOutputBytes) else { throw InvarError("RESOURCE_LIMIT", "Invalid run budget", exitCode: 6) }
    }
    public static func profile(_ value: NativeProfile) throws {
        guard value.kind == "swift-modules-json/1", value.target == "arm64-apple-macosx27.0", value.modules.count <= 32,
            !value.harness.isEmpty, !value.compiler.isEmpty, value.compiler.hasPrefix("/"), value.sdk.hasPrefix("/"), value.toolsDirectory.hasPrefix("/") else { throw InvarError("UNSUPPORTED_NATIVE_PROFILE", "Native profile requires explicit macOS 27 arm64 compiler/SDK/tool roots", exitCode: 3) }
        let names = Set(value.modules.map(\.name)), sources = value.modules.flatMap(\.sources) + value.harness
        guard names.count == value.modules.count, !sources.isEmpty, sources.count <= 256, Set(sources).count == sources.count else { throw InvarError("INVALID_CONFIGURATION", "Duplicate or excessive native modules/sources", exitCode: 2) }
        for path in sources { _ = try Canonical.relative(path); guard path.hasSuffix(".swift") else { throw InvarError("UNSUPPORTED_NATIVE_PROFILE", "Only Swift sources are supported", exitCode: 3) } }
        for module in value.modules {
            let name = module.name.utf8
            guard !module.sources.isEmpty, name.count <= 64, let first = name.first, (65...90).contains(first) || (97...122).contains(first) || first == 95,
                name.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 }), module.name != "InvarHarness",
                Set(module.dependencies).isSubset(of: names), Set(module.dependencies).count == module.dependencies.count else { throw InvarError("INVALID_CONFIGURATION", "Invalid native module/dependencies", exitCode: 2) }
        }
        var pending = value.modules, complete = Set<String>()
        while !pending.isEmpty {
            guard let index = pending.firstIndex(where: { Set($0.dependencies).isSubset(of: complete) }) else { throw InvarError("INVALID_DAG", "Native module dependency cycle", exitCode: 2) }
            complete.insert(pending.remove(at: index).name)
        }
    }
    public static func validate(_ plan: VerificationPlan) throws {
        try budget(plan.body.budget)
        guard plan.body.executorIdentity.utf8.count == 64, plan.body.executorIdentity.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
            plan.body.schemaVersion == 2, try Canonical.identity(plan.body) == plan.id,
            plan.body.input.id == plan.body.input.manifestDigest, plan.body.input.byteCount >= 0, plan.body.input.fileCount >= 0, validDigest(plan.body.input.id), validDigest(plan.body.input.semanticDigest),
            !plan.body.jobs.isEmpty, plan.body.jobs.count <= 500 else { throw InvarError("INVALID_PLAN", "Invalid plan schema, identities or obligation count", exitCode: 2) }
        let ids = Set(plan.body.jobs.map(\.id))
        guard ids.count == plan.body.jobs.count else { throw InvarError("INVALID_DAG", "Duplicate job identity", exitCode: 2) }
        var visited = Set<String>(), pending = plan.body.jobs
        for job in pending {
            if let project = job.project { guard project.budget == plan.body.budget else { throw InvarError("INVALID_PLAN","Project operational budget differs from its approved configuration") } }
            try validateJob(job,executorIdentity: plan.body.executorIdentity)
            guard Set(job.dependencies).isSubset(of: ids) else { throw InvarError("INVALID_DAG","Unknown prerequisite") }
        }
        let configuration = VerificationConfiguration(architecture: plan.body.jobs.compactMap(\.policy), formal: plan.body.jobs.compactMap(\.formal), native: plan.body.jobs.compactMap(\.native), fuzz: plan.body.jobs.compactMap(\.fuzz), project: plan.body.jobs.compactMap(\.project).first)
        let configurationBytes = try Canonical.encode(configuration)
        _ = try ConfigurationReader.decode(configurationBytes)
        guard try configuration.identity() == plan.body.configurationDigest else { throw InvarError("INVALID_PLAN", "Configuration digest differs from bound obligations", exitCode: 2) }
        while !pending.isEmpty {
            guard let index = pending.firstIndex(where: { Set($0.dependencies).isSubset(of: visited) }) else { throw InvarError("INVALID_DAG", "Dependency cycle", exitCode: 2) }
            visited.insert(pending.remove(at: index).id)
        }
    }
    public static func descriptor(_ value: JobDescriptor) throws {
        try budget(value.budget)
        guard value.schemaVersion == 2, validDigest(value.planID), validDigest(value.executorIdentity),
            validDigest(value.input.id), value.input.id == value.input.manifestDigest,
            validDigest(value.input.semanticDigest), validDigest(value.input.graphDigest),
            value.input.byteCount >= 0, value.input.fileCount >= 0 else { throw InvarError("INVALID_PLAN","Invalid worker descriptor binding") }
        if let project = value.job.project { guard project.budget == value.budget else { throw InvarError("INVALID_PLAN","Project worker budget differs from its configuration") } }
        try validateJob(value.job,executorIdentity: value.executorIdentity)
    }
    private static func validateJob(_ job: VerificationJob,executorIdentity: String) throws {
        guard (job.backend == "project") == (job.project != nil), (job.backend == "modelGeneration") == (job.modelSource != nil), job.backend == "formal" || job.compilation == nil,
            ["formal","fuzz"].contains(job.backend) || job.oracle == nil,
            job.toolchainIdentity.map(validDigest) ?? true else { throw InvarError("INVALID_PLAN","Unexpected artifact/tool identity for backend") }
            try identifier(job.id)
            guard job.memoryMiB > 0, job.memoryMiB <= 131072, Set(job.dependencies).count == job.dependencies.count else { throw InvarError("INVALID_DAG", "Invalid resource/dependency declaration", exitCode: 2) }
            switch job.backend {
            case "modelGeneration":
                guard let source = job.modelSource, !source.language.isEmpty, source.supportsModelSelection,
                    job.inputs.count == 1, let file = job.inputs.first, source.path == file.path, source.sourceDigest == file.digest,
                    source.kind == "file" || (source.startByte ?? -1) >= 0 && (source.endByte ?? -1) > (source.startByte ?? -1) && (source.endByte ?? Int.max) <= file.byteCount,
                    !job.required, job.approved, job.dependencies.isEmpty, job.formal == nil, job.native == nil, job.fuzz == nil, job.policy == nil, job.toolchainIdentity == nil
                else { throw InvarError("INVALID_PLAN","Invalid source-only model descriptor") }
            case "project":
                guard let check = job.project, job.memoryMiB == check.budget.memoryMiB, check.id == job.id, check.approved == job.approved, check.required == job.required,
                    job.policy == nil, job.formal == nil, job.native == nil, job.fuzz == nil, !job.inputs.isEmpty,
                    check.contracts.allSatisfy({ path in job.inputs.contains { $0.path == path } }) else { throw InvarError("INVALID_PLAN","Project job differs from its reviewed workflow") }
                try check.validate()
            case "static": guard let policy = job.policy, policy.id == job.id, policy.approved == job.approved, policy.required == job.required, job.formal == nil, job.native == nil, job.fuzz == nil else { throw InvarError("INVALID_PLAN", "Static job differs from its obligation", exitCode: 2) }
            case "formal":
                guard let check = job.formal, job.memoryMiB == check.admissionMemoryMiB, check.id == job.id, check.approved == job.approved, check.required == job.required, job.policy == nil, job.native == nil, job.fuzz == nil, job.oracle != nil, job.compilation != nil else { throw InvarError("INVALID_PLAN", "Formal job differs from its obligation", exitCode: 2) }
                _ = try Canonical.relative(check.source); _ = try Canonical.relative(check.specification)
            case "native":
                guard let check = job.native, check.id == job.id, check.approved == job.approved, check.required == job.required, job.fuzz == nil, job.formal == nil, job.policy == nil else { throw InvarError("INVALID_PLAN", "Native job differs from its obligation", exitCode: 2) }
                try profile(check.profile)
            case "fuzz":
                guard let check = job.fuzz, check.id == job.id, check.approved == job.approved, check.required == job.required, job.native == nil, job.formal == nil, job.policy == nil else { throw InvarError("INVALID_PLAN", "Fuzz job differs from its obligation", exitCode: 2) }
                try profile(check.profile); _ = try Canonical.relative(check.corpus)
            default: throw InvarError("UNSUPPORTED_BACKEND", "Unknown planned backend", exitCode: 3)
            }
            if let path = job.formal?.specification ?? job.fuzz?.corpus {
                guard let oracle = job.oracle, oracle.path == path, oracle.byteCount >= 0, oracle.byteCount <= 5 * 1024 * 1024, validDigest(oracle.digest) else { throw InvarError("INVALID_PLAN", "Oracle reference differs from obligation", exitCode: 2) }
            }
            if let compilation = job.compilation {
                let key = try PreparedFormalUnit.key(sourceDigest: compilation.sourceDigest,language: compilation.language,executorIdentity: compilation.executorIdentity)
                guard compilation.id == key, compilation.executorIdentity == executorIdentity, ["swift","rust"].contains(compilation.language), validDigest(compilation.sourceDigest), validDigest(compilation.manifest.sha256), compilation.manifest.id == compilation.manifest.sha256, compilation.manifest.byteCount > 0, compilation.manifest.profile == "formal-compilation/2", validDigest(compilation.evidence.sha256), compilation.evidence.id == compilation.evidence.sha256, compilation.evidence.byteCount > 0, compilation.evidence.profile == "formal-evidence/1" else { throw InvarError("INVALID_PLAN","Formal preparation identity differs") }
            }
        guard Set(job.inputs.map(\.path)).count == job.inputs.count else { throw InvarError("INVALID_PLAN","Duplicate sparse input") }
        for entry in job.inputs {
            _ = try Canonical.relative(entry.path)
            guard entry.byteCount >= 0, validDigest(entry.digest) else { throw InvarError("INVALID_PLAN","Invalid sparse input") }
        }
        let expected: Set<String>
        if job.project != nil { expected = Set(job.inputs.map(\.path)) }
        else if let path = job.modelSource?.path { expected = [path] }
        else if let formal = job.formal { expected = Set([formal.source,formal.specification]) }
        else if let native = job.native { expected = Set(native.profile.modules.flatMap(\.sources) + native.profile.harness) }
        else if let fuzz = job.fuzz { expected = Set(fuzz.profile.modules.flatMap(\.sources) + fuzz.profile.harness + [fuzz.corpus]) }
        else { expected = [] }
        guard Set(job.inputs.map(\.path)) == expected else { throw InvarError("INVALID_PLAN","Descriptor read set differs from enforced profile") }
        if let oracle = job.oracle { guard job.inputs.contains(oracle) else { throw InvarError("INVALID_PLAN","Oracle is absent from sparse read set") } }
        if let compilation = job.compilation, let formal = job.formal {
            guard job.inputs.contains(where: { $0.path == formal.source && $0.digest == compilation.sourceDigest }) else { throw InvarError("INVALID_PLAN","Prepared source differs from sparse input") }
        }
        let configuration = VerificationConfiguration(architecture: job.policy.map { [$0] } ?? [],formal: job.formal.map { [$0] } ?? [],native: job.native.map { [$0] } ?? [],fuzz: job.fuzz.map { [$0] } ?? [],project: job.project)
        let bytes = try Canonical.encode(configuration)
        _ = try ConfigurationReader.decode(bytes)
    }
    public static func bind(_ plan: VerificationPlan,to inventory: ScopeInventory) throws {
        let input = try VerificationInput.reference(inventory)
        guard input == plan.body.input else { throw InvarError("INVALID_PLAN","Fixed inventory differs from plan reference") }
        for job in plan.body.jobs {
            if let project = job.project { guard job.inputs == inventory.inputs.filter({ project.includes($0.path) }) else { throw InvarError("INPUT_MISMATCH","Project plan omitted captured inputs") } }
            if let source = job.modelSource, !inventory.entities.contains(source) { throw InvarError("INPUT_MISMATCH","Model source is absent from the snapshot") }
            guard job.inputs.allSatisfy({ inventory.inputs.contains($0) }) else { throw InvarError("INVALID_PLAN","Sparse inputs are absent from fixed manifest") }
            if let oracle = job.oracle { guard inventory.inputs.contains(oracle) else { throw InvarError("INVALID_PLAN","Oracle is absent from fixed manifest") } }
            if let formal = job.formal, let compilation = job.compilation {
                guard inventory.inputs.contains(where: { $0.path == formal.source && $0.digest == compilation.sourceDigest }) else { throw InvarError("INVALID_PLAN","Prepared source is absent from fixed manifest") }
            }
        }
    }
    private static func validDigest(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    public static func evidence(_ value: VerificationEvidence, job: any VerificationObligation) throws {
        guard value.jobID == job.id,
            ["completed", "cancelled", "timeout", "resourceLimited", "toolError", "unsupported", "blocked"].contains(value.execution),
            ["holdsWithinScope", "violatedWithinScope", "unknown", "notEvaluated", "noViolationObservedWithinBudget"].contains(value.outcome),
            validDigest(value.inputID), ["completeWithinScope","witnessWithinScope","unknown"].contains(value.adequacy),
            Set(value.artifacts.map(\.id)).count == value.artifacts.count,
            value.artifacts.allSatisfy({ validDigest($0.id) && $0.id == $0.sha256 && $0.byteCount >= 0 && !$0.profile.isEmpty }),
            (job.backend == "project" && value.domain == "projectContract" && value.translation == "notApplicable") ||
            (job.backend == "static" && value.domain == "architecture" && value.translation == "notApplicable") ||
                (job.backend == "modelGeneration" && value.outcome == "notEvaluated" && value.domain == "generatedModel" && value.translation == "unvalidated") ||
                (job.backend == "formal" && value.domain == "generatedModel" && value.translation == "unvalidated") ||
                (["native", "fuzz"].contains(job.backend) && value.domain == "nativeExecution" && value.translation == "notApplicable"),
            (job.backend != "fuzz" || value.outcome != "holdsWithinScope"),
            (job.backend == "fuzz" || value.outcome != "noViolationObservedWithinBudget"),
            value.reproductionKey.map({ $0.utf8.count == 64 && $0.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) }) ?? true,
            value.resources.values.allSatisfy({ $0.isFinite && $0 >= 0 }),
            value.execution == "completed" || ["notEvaluated", "unknown"].contains(value.outcome) else { throw InvarError("INVALID_RESULT", "Evidence violates its job/status/domain contract") }
    }
}
