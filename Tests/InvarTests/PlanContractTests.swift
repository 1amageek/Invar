import Foundation
import Testing
import VerificationCore

@Suite struct PlanContractTests {
    static let profile = NativeProfile(compiler: "/tools/swiftc", sdk: "/sdk", toolsDirectory: "/tools", modules: [], harness: ["Harness.swift"])
    static func plan(_ job: VerificationJob, configurationDigest: String? = nil) throws -> VerificationPlan {
        let inventory = DomainTests.inventory()
        let configuration = VerificationConfiguration(architecture: job.policy.map { [$0] } ?? [], formal: job.formal.map { [$0] } ?? [], native: job.native.map { [$0] } ?? [], fuzz: job.fuzz.map { [$0] } ?? [])
        let digest = try configuration.identity()
        let body = PlanBody(input: try VerificationInput.reference(inventory), executorIdentity: String(repeating: "0", count: 64), configurationDigest: configurationDigest ?? digest, jobs: [job], budget: RunBudget())
        return VerificationPlan(id: try Canonical.identity(body), body: body)
    }
    @Test func generationIsBoundToOneSourceAndCannotReportAProof() throws {
        let file = InputEntry(path: "Source.swift",digest: Canonical.digest(Data("source".utf8)),byteCount: 6)
        let entity = EntityRecord(id: "f",kind: "function",language: "swift",name: "f",path: file.path,sourceDigest: file.digest,startByte: 0,endByte: 6)
        let job = VerificationJob(id: "generate-model",backend: "modelGeneration",required: false,approved: true,inputs: [file],modelSource: entity)
        let plan = try Self.plan(job)
        try PlanValidation.validate(plan)
        let proof = VerificationEvidence(inputID: plan.body.input.id,jobID: job.id,execution: "completed",outcome: "holdsWithinScope",domain: "generatedModel",translation: "unvalidated",scope: "source",adequacy: "unknown",detail: "",startedAt: "",finishedAt: "")
        #expect(throws: InvarError.self) { try PlanValidation.evidence(proof,job: job) }
        let mismatched = VerificationJob(id: job.id,backend: job.backend,required: false,approved: true,inputs: [],modelSource: entity)
        #expect(throws: InvarError.self) { try PlanValidation.validate(Self.plan(mismatched)) }
    }
    @Test func savedPlansCannotBypassNativeCountOrFuzzRangeValidation() throws {
        let native = NativeCheck(id: "native", profile: Self.profile, expectedTestCount: 0, approved: true)
        let harness = InputEntry(path: "Harness.swift",digest: Canonical.digest(Data("harness".utf8)),byteCount: 7)
        let nativeJob = VerificationJob(id: native.id, backend: "native", required: true, approved: true, inputs: [harness], native: native)
        let validNative = NativeCheck(id: "native",profile: Self.profile,expectedTestCount: 1,approved: true)
        let validNativePlan = try Self.plan(VerificationJob(id: validNative.id,backend: "native",required: true,approved: true,inputs: [harness],native: validNative))
        try PlanValidation.validate(validNativePlan)
        let invalidNative = try Self.plan(nativeJob)
        #expect(throws: (any Error).self) { try PlanValidation.validate(invalidNative) }
        let fuzz = FuzzCheck(id: "fuzz", profile: Self.profile, corpus: "corpus.json", seed: "7", minimum: "9", maximum: "1", iterations: -1, approved: true)
        let corpus = InputEntry(path: "corpus.json",digest: Canonical.digest(Data("[]".utf8)),byteCount: 2)
        let fuzzJob = VerificationJob(id: fuzz.id, backend: "fuzz", required: true, approved: true, inputs: [harness,corpus], oracle: corpus, fuzz: fuzz)
        let invalidFuzz = try Self.plan(fuzzJob)
        #expect(throws: (any Error).self) { try PlanValidation.validate(invalidFuzz) }
    }
    @Test func planHashDoesNotReplaceConfigurationAuthority() throws {
        let job = SchedulerTests.job("rule")
        let valid = try Self.plan(job)
        try PlanValidation.validate(valid)
        let changedBinding = try Self.plan(job, configurationDigest: "unrelated-configuration")
        #expect(throws: (any Error).self) { try PlanValidation.validate(changedBinding) }
    }
    @Test func configurationIdentityIgnoresOnlyDeclarationOrder() throws {
        let a = ArchitecturePolicy(id: "a", kind: "cycle", approved: true)
        let b = ArchitecturePolicy(id: "b", kind: "cycle", approved: true)
        #expect(try VerificationConfiguration(architecture: [a, b]).identity() == VerificationConfiguration(architecture: [b, a]).identity())
        #expect(try VerificationConfiguration(architecture: [a, b]).identity() != VerificationConfiguration(architecture: [a]).identity())
    }
    @Test func fuzzBudgetCannotBePromotedToProof() throws {
        let check = FuzzCheck(id: "fuzz", profile: Self.profile, corpus: "corpus.json", seed: "7", minimum: "0", maximum: "10", iterations: 3, approved: true)
        let job = VerificationJob(id: "fuzz", backend: "fuzz", required: true, approved: true, fuzz: check)
        let fakeProof = try DomainTests.evidence("fuzz", domain: "nativeExecution")
        let association = try DomainTests.association(fakeProof)
        #expect(!RunAssessment.accepts(fakeProof,for: job,association: association))
        #expect(throws: (any Error).self) { try PlanValidation.evidence(fakeProof, job: job) }
    }
}

extension PlanContractTests {
    @Test func capturedScopeComparisonExcludesOnlySnapshotIdentityAndRetainsUnknownAndOperationalBounds() throws {
        let original = DomainTests.inventory()
        let next = ScopeInventory(workspaceID: original.workspaceID,snapshotID: "another-index-generation",contextDigest: original.contextDigest,metadata: original.metadata,entities: original.entities,facts: original.facts,coverage: original.coverage,inputs: original.inputs,originalRecords: original.originalRecords)
        let changedContext = ScopeInventory(workspaceID: original.workspaceID,snapshotID: next.snapshotID,contextDigest: "different-context",metadata: original.metadata,entities: original.entities,facts: original.facts,coverage: original.coverage,inputs: original.inputs,originalRecords: original.originalRecords)
        func metadata(_ inventory: ScopeInventory,budget: RunBudget = RunBudget(),job: VerificationJob = SchedulerTests.job("rule")) throws -> SchedulingPlan {
            let input = try VerificationInput.reference(inventory), configuration = VerificationConfiguration(architecture: job.policy.map { [$0] } ?? [])
            let digest = try configuration.identity()
            let body = PlanBody(input: input,executorIdentity: String(repeating: "0",count: 64),configurationDigest: digest,jobs: [job],budget: budget)
            let id = try Canonical.identity(body)
            return try SchedulingPlan(VerificationPlan(id: id,body: body))
        }
        let first = try metadata(original), second = try metadata(next)
        #expect(first.id != second.id && first.input.id != second.input.id)
        #expect(first.capturedScopeDigest == second.capturedScopeDigest)
        #expect(first.input.dependencyStatus == "unknown" && second.input.dependencyStatus == "unknown")
        let context = try metadata(changedContext), timeout = try metadata(next,budget: RunBudget(timeoutSeconds: 42)), memory = try metadata(next,job: SchedulerTests.job("rule",memory: 128))
        #expect(context.capturedScopeDigest != first.capturedScopeDigest)
        #expect(timeout.capturedScopeDigest != first.capturedScopeDigest)
        #expect(memory.capturedScopeDigest != first.capturedScopeDigest)
    }
}
