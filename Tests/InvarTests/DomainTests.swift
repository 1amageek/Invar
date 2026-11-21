import Foundation
import Testing
import VerificationCore
import VerificationDiscovery
import VerificationPlanner
import VerificationStore

@Suite struct DomainTests {
    static let entityA = EntityRecord(id: "a", kind: "module", language: "swift", name: "A")
    static let entityB = EntityRecord(id: "b", kind: "module", language: "swift", name: "B")
    static func inventory(facts: [FactRecord] = [], complete: Bool = true, snapshot: String = "snapshot") -> ScopeInventory {
        ScopeInventory(workspaceID: "workspace", snapshotID: snapshot, contextDigest: "context", metadata: [:], entities: [entityA, entityB], facts: facts,
            coverage: [CoverageRecord(producer: "test", scope: "workspace", freshness: "current", completeness: complete ? "completeWithinScope" : "partial")], inputs: [])
    }
    static func evidence(_ id: String, domain: String = "architecture", translation: String = "notApplicable") throws -> VerificationEvidence {
        let inputID = try Canonical.identity(inventory())
        return VerificationEvidence(inputID: inputID,jobID: id, execution: "completed", outcome: "holdsWithinScope", domain: domain, translation: translation,
            scope: "fixture", adequacy: "completeWithinScope", detail: "fixture", startedAt: "now", finishedAt: "now")
    }
    @Test func ruleWitnessAndAbsenceHaveDifferentCompletenessRequirements() throws {
        let edge = FactRecord(id: "ab", kind: "dependsOn", source: "a", target: "b", producer: "test", scope: "workspace")
        let policy = ArchitecturePolicy(id: "no-ab", kind: "forbiddenDependency", from: EntitySelector(id: "a"), to: EntitySelector(id: "b"), approved: true)
        let evaluator = ArchitectureRuleEvaluator()
        let violation = try evaluator.evaluate(policy, inventory: Self.inventory(facts: [edge], complete: false))
        #expect(violation.outcome == "violatedWithinScope")
        #expect(violation.witnessFactIDs == ["ab"])
        #expect(violation.adequacy == "witnessWithinScope")
        #expect(try evaluator.evaluate(policy, inventory: Self.inventory(complete: false)).outcome == "unknown")
        #expect(try evaluator.evaluate(policy, inventory: Self.inventory()).outcome == "holdsWithinScope")
    }
    @Test func selectorsCannotProveAnEmptyTarget() throws {
        let policy = ArchitecturePolicy(id: "empty", kind: "forbiddenDependency", from: EntitySelector(name: "Missing"), to: EntitySelector(id: "b"), approved: true)
        #expect(try ArchitectureRuleEvaluator().evaluate(policy, inventory: Self.inventory()).outcome == "unknown")
    }
    @Test func cyclesAreExplicitPoliciesAndReturnExactFacts() throws {
        let facts = [FactRecord(id: "ab", kind: "calls", source: "a", target: "b", producer: "test", scope: "workspace"), FactRecord(id: "ba", kind: "calls", source: "b", target: "a", producer: "test", scope: "workspace")]
        let result = try ArchitectureRuleEvaluator().evaluate(ArchitecturePolicy(id: "acyclic", kind: "cycle", relations: ["calls"]), inventory: Self.inventory(facts: facts))
        #expect(result.witnessFactIDs == ["ab", "ba"])
        #expect(result.detail.contains("not a runtime defect"))
    }
    static func association(_ evidence: VerificationEvidence) throws -> EvidenceAssociation {
        let input = try VerificationInput.reference(inventory())
        return EvidenceAssociation.make(evidence: evidence,changeRevisionID: nil,input: input,status: "matchesInputs",basis: "Fixture exact input",unknownBoundaries: [],reuseDecision: "originalExecution")
    }
    @Test func evidenceCannotCrossBackendDomains() throws {
        let formal = FormalCheck(id: "proof", source: "Source.swift", mode: "finite", specification: "oracle.json", toolchain: "/tools", approved: true, acceptUnvalidatedModel: true)
        let job = VerificationJob(id: "proof", backend: "formal", required: true, approved: true, formal: formal)
        let architecture = try Self.evidence("proof")
        let wrongJob = try Self.evidence("another",domain: "generatedModel",translation: "unvalidated")
        let model = try Self.evidence("proof",domain: "generatedModel",translation: "unvalidated")
        let architectureAssociation = try Self.association(architecture), wrongAssociation = try Self.association(wrongJob), modelAssociation = try Self.association(model)
        #expect(!RunAssessment.accepts(architecture,for: job,association: architectureAssociation))
        #expect(!RunAssessment.accepts(wrongJob,for: job,association: wrongAssociation))
        #expect(RunAssessment.accepts(model,for: job,association: modelAssociation))
    }
    @Test func configurationRejectsUnknownAndEmptySelectors() throws {
        #expect(throws: (any Error).self) { try ConfigurationReader.decode(Data(#"{"schemaVersion":1,"architecture":[{"id":"rule","kind":"cycle","from":{"name":""}}]}"#.utf8)) }
        #expect(throws: (any Error).self) { try ConfigurationReader.decode(Data(#"{"schemaVersion":1,"formal":[],"unknown":true}"#.utf8)) }
        #expect(throws: (any Error).self) { try ConfigurationReader.decode(Data(#"{"schemaVersion":1,"architecture":[{"id":"../escape","kind":"cycle"}]}"#.utf8)) }
    }
    @Test func inputFingerprintIgnoresOnlyIndexGeneration() throws {
        #expect(try InputIdentity.digest(Self.inventory(snapshot: "one")) == InputIdentity.digest(Self.inventory(snapshot: "two")))
        #expect(try Canonical.identity(Self.inventory(snapshot: "one")) != Canonical.identity(Self.inventory(snapshot: "two")))
    }
    @Test func storeRoundTripsAndRejectsChangedInputAndClosedWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-store-test-" + UUID().uuidString)
        let bytes = Data("func example() -> Int { 1 }".utf8)
        let inventory = ScopeInventory(workspaceID: "w", snapshotID: "s", contextDigest: "c", metadata: [:], entities: [], facts: [], coverage: [], inputs: [InputEntry(path: "Source.swift", digest: Canonical.digest(bytes), byteCount: bytes.count)])
        let capture = CapturedWorkspace(inventory: inventory, files: ["Source.swift": bytes])
        let store = try SQLiteVerificationStore(root: root)
        let id = try await store.saveInput(capture)
        let payload = try await store.inputRoot(id)
        #expect(try Data(contentsOf: payload.appendingPathComponent("Source.swift")) == bytes)
        try Data("changed".utf8).write(to: payload.appendingPathComponent("Source.swift"))
        await #expect(throws: (any Error).self) { try await store.inputRoot(id) }
        try bytes.write(to: payload.appendingPathComponent("Source.swift"))
        try await store.shutdown()
        await #expect(throws: (any Error).self) { try await store.saveInput(capture) }
        try FileManager.default.removeItem(at: root)
    }
    @Test(.timeLimit(.minutes(1))) func concurrentClientsPublishTheSameSealedInputIdempotently() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("invar-concurrent-store-" + UUID().uuidString)
        let first = try SQLiteVerificationStore(root: root), second = try SQLiteVerificationStore(root: root)
        let bytes = Data(repeating: 65, count: 1024 * 1024)
        let inventory = ScopeInventory(workspaceID: "workspace", snapshotID: "snapshot", contextDigest: "context", metadata: [:], entities: [], facts: [], coverage: [], inputs: [InputEntry(path: "Source.swift", digest: Canonical.digest(bytes), byteCount: bytes.count)])
        let capture = CapturedWorkspace(inventory: inventory, files: ["Source.swift": bytes])
        let ids = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<20 { group.addTask { try await (index % 2 == 0 ? first : second).saveInput(capture) } }
            var results: [String] = []
            for try await id in group { results.append(id) }
            return results
        }
        #expect(ids.count == 20 && Set(ids).count == 1)
        let input = try await first.inputRoot(ids[0])
        #expect(try Data(contentsOf: input.appendingPathComponent("Source.swift")) == bytes)
        let retained = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("inputs").path)
        #expect(retained == [ids[0]])
        try await first.shutdown(); try await second.shutdown(); try FileManager.default.removeItem(at: root)
    }

    @Test(.timeLimit(.minutes(1))) func competingImmutableRunWritersCannotOverwriteEachOther() async throws {
        let (first, plan, root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let second = try SQLiteVerificationStore(root: root)
        let holds = try ReplayTests.run("same-run-id", plan: plan.id, outcome: "holdsWithinScope")
        let violated = try ReplayTests.run("same-run-id", plan: plan.id, outcome: "violatedWithinScope")
        let results = await withTaskGroup(of: String.self) { group in
            for (store, run) in [(first, holds), (second, violated)] {
                group.addTask {
                    do { try await store.saveRun(run); return "saved" }
                    catch let error as InvarError { return error.code }
                    catch { return "unexpected-error" }
                }
            }
            var values: [String] = []
            for await result in group { values.append(result) }
            return values.sorted()
        }
        #expect(results == ["IMMUTABLE_CONFLICT", "saved"])
        let retained = try await first.loadRun("same-run-id")
        #expect(retained == holds || retained == violated)
        #expect(try await second.loadRun("same-run-id") == retained)
        try await first.shutdown(); try await second.shutdown(); try FileManager.default.removeItem(at: root)
    }

}
