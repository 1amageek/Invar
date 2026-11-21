import Foundation
import VerificationCore

public struct PlanBuilder: VerificationPlanning {
    public init() {}
    public func build(inventory: ScopeInventory, inputID: String, executorIdentity: String, configuration: VerificationConfiguration,
        specifications: [String: Data], compilations: [String: PreparedFormalUnit] = [:], toolchains: [String: String], budget: RunBudget) throws -> VerificationPlan {
        try PlanValidation.budget(budget)
        var jobs: [VerificationJob] = [], diagnostics: [String] = []
        for policy in configuration.architecture {
            jobs.append(VerificationJob(id: policy.id, backend: "static", required: policy.required, approved: policy.approved, policy: policy))
            if !policy.approved { diagnostics.append("Unapproved hypothesis: \(policy.id)") }
        }
        for check in configuration.formal {
            guard inventory.inputs.contains(where: { $0.path == check.source }), let spec = specifications[check.id] else {
                throw InvarError("INPUT_UNAVAILABLE", "Missing exact source/specification for \(check.id)")
            }
            guard let oracle = inventory.inputs.first(where: { $0.path == check.specification }), oracle.byteCount == spec.count, oracle.digest == Canonical.digest(spec), let compilation = compilations[check.id], compilation.sourceDigest == inventory.inputs.first(where: { $0.path == check.source })?.digest else { throw InvarError("INPUT_MISMATCH","Formal preparation/oracle differs from fixed inputs") }
            let memory = check.admissionMemoryMiB
            jobs.append(VerificationJob(id: check.id, backend: "formal", required: check.required, approved: check.approved,
                formal: check, inputs: inventory.inputs.filter { $0.path == check.source || $0.path == check.specification }, oracle: oracle, compilation: compilation, toolchainIdentity: toolchains[check.id], memoryMiB: memory))
            if toolchains[check.id] == nil { diagnostics.append("Formal runtime is unavailable for \(check.id)") }
            if !check.approved { diagnostics.append("Unapproved hypothesis: \(check.id)") }
            if memory > budget.memoryMiB { diagnostics.append("Job \(check.id) cannot fit the memory admission budget") }
        }
        for check in configuration.native {
            let sources = check.profile.modules.flatMap(\.sources) + check.profile.harness
            guard sources.allSatisfy({ path in inventory.inputs.contains { $0.path == path } }) else { throw InvarError("INPUT_UNAVAILABLE", "Native profile has uncaptured sources") }
            jobs.append(VerificationJob(id: check.id, backend: "native", required: check.required, approved: check.approved, inputs: inventory.inputs.filter { sources.contains($0.path) }, toolchainIdentity: toolchains[check.id], memoryMiB: 1536, native: check))
        }
        for check in configuration.fuzz {
            let sources = check.profile.modules.flatMap(\.sources) + check.profile.harness
            guard sources.allSatisfy({ path in inventory.inputs.contains { $0.path == path } }), let corpus = specifications[check.id] else { throw InvarError("INPUT_UNAVAILABLE", "Fuzz profile has uncaptured sources/corpus") }
            guard let oracle = inventory.inputs.first(where: { $0.path == check.corpus }), oracle.byteCount == corpus.count, oracle.digest == Canonical.digest(corpus) else { throw InvarError("INPUT_MISMATCH","Corpus differs from fixed inputs") }
            jobs.append(VerificationJob(id: check.id, backend: "fuzz", required: check.required, approved: check.approved, inputs: inventory.inputs.filter { sources.contains($0.path) || $0.path == check.corpus }, oracle: oracle, toolchainIdentity: toolchains[check.id], memoryMiB: 1536, fuzz: check))
        }
        if let project = configuration.project {
            try project.validate()
            guard project.budget == budget, project.contracts.allSatisfy({ path in inventory.inputs.contains { $0.path == path } }) else { throw InvarError("INPUT_MISMATCH","Project budget/contracts differ from the sealed request") }
            jobs.append(VerificationJob(id: project.id,backend: "project",required: project.required,approved: project.approved,inputs: inventory.inputs.filter { project.includes($0.path) },memoryMiB: budget.memoryMiB,project: project))
        }
        guard !jobs.isEmpty else { throw InvarError("MISSING_ORACLE", "Configuration contains no obligations; empty success is forbidden", exitCode: 2) }
        let input = try VerificationInput.reference(inventory)
        guard input.id == inputID else { throw InvarError("INPUT_MISMATCH","Plan inventory differs from sealed input reference") }
        let body = PlanBody(input: input, executorIdentity: executorIdentity, configurationDigest: try configuration.identity(),
            jobs: jobs.sorted { $0.id < $1.id }, budget: budget, diagnostics: diagnostics)
        let plan = VerificationPlan(id: try Canonical.identity(body), body: body)
        try PlanValidation.validate(plan)
        return plan
    }
}
