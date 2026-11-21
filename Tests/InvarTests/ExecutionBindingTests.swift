import Foundation
import Testing
import VerificationCore

@Suite struct ExecutionBindingTests {
    func descriptor(source: String = "source",count: Int = 1,compiler: String = "/tools/swiftc",tool: String = String(repeating: "1",count: 64),executor: String = String(repeating: "0",count: 64),budget: RunBudget = RunBudget(),snapshot: String = "snapshot",context: String = "context",planID: String = String(repeating: "2",count: 64)) throws -> JobDescriptor {
        let bytes = Data(source.utf8), harness = Data("harness".utf8)
        let entries = [InputEntry(path: "Value.swift",digest: Canonical.digest(bytes),byteCount: bytes.count),InputEntry(path: "Harness.swift",digest: Canonical.digest(harness),byteCount: harness.count)]
        let inventory = ScopeInventory(workspaceID: "workspace",snapshotID: snapshot,contextDigest: context,metadata: ["dependencyStatus":"unknown"],entities: [],facts: [],coverage: [],inputs: entries)
        let profile = NativeProfile(compiler: compiler,sdk: "/sdk",toolsDirectory: "/tools",modules: [NativeModule(name: "Values",sources: ["Value.swift"])],harness: ["Harness.swift"])
        let check = NativeCheck(id: "native",profile: profile,expectedTestCount: count,approved: true)
        let job = VerificationJob(id: check.id,backend: "native",required: true,approved: true,inputs: entries,toolchainIdentity: tool,memoryMiB: 1536,native: check)
        return JobDescriptor(planID: planID,input: try VerificationInput.reference(inventory),job: job,executorIdentity: executor,budget: budget)
    }
    @Test func completeEnforcedReadSetKeyBindsEveryExecutionDimension() throws {
        let baseline = try descriptor()
        let computed = try ExecutionBinding.key(baseline)
        let key = try #require(computed)
        let changes = [try descriptor(source: "changed"),try descriptor(count: 2),try descriptor(compiler: "/other/swiftc"),try descriptor(tool: String(repeating: "3",count: 64)),try descriptor(executor: String(repeating: "4",count: 64)),try descriptor(budget: RunBudget(timeoutSeconds: 121)),try descriptor(context: "changed-context")]
        for changed in changes { #expect(try ExecutionBinding.key(changed) != key) }
        let otherGeneration = try descriptor(snapshot: "different",planID: String(repeating: "5",count: 64))
        #expect(otherGeneration.input.id != baseline.input.id)
        #expect(try ExecutionBinding.key(otherGeneration) == key)
        #expect(baseline.input.dependencyStatus == "unknown")
    }
    @Test func workerReadSetCannotOmitDuplicateOrAddUncapturedProfileInputs() throws {
        let baseline = try descriptor(), original = baseline.job
        for inputs in [Array(original.inputs.dropLast()),original.inputs + [original.inputs[0]],original.inputs + [InputEntry(path: "Extra.swift",digest: Canonical.digest(Data()),byteCount: 0)]] {
            let job = VerificationJob(id: original.id,backend: original.backend,required: original.required,approved: original.approved,inputs: inputs,toolchainIdentity: original.toolchainIdentity,memoryMiB: original.memoryMiB,native: original.native)
            let changed = JobDescriptor(planID: baseline.planID,input: baseline.input,job: job,executorIdentity: baseline.executorIdentity,budget: baseline.budget)
            #expect(throws: InvarError.self) { try PlanValidation.descriptor(changed) }
        }
    }
}
