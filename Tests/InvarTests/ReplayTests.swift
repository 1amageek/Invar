import Foundation
import Testing
import VerificationCore
import VerificationStore

@Suite struct ReplayTests {
    static func run(_ id: String, plan: String, outcome: String, execution: String = "completed") throws -> VerificationRun {
        let input = try VerificationInput.reference(DomainTests.inventory())
        let evidence = VerificationEvidence(inputID: input.id,jobID: "a", execution: execution, outcome: outcome, domain: "architecture", translation: "notApplicable", scope: "fixture", adequacy: "completeWithinScope", detail: "fixture", startedAt: "now", finishedAt: "now")
        let association = EvidenceAssociation.make(evidence: evidence,changeRevisionID: nil,input: input,status: "matchesInputs",basis: "Fixture exact input",unknownBoundaries: [],reuseDecision: "originalExecution")
        return VerificationRun(id: id, planID: plan, attempts: [evidence], associations: [association], accepted: outcome == "holdsWithinScope")
    }
    @Test func replayDoesNotEraseAnUnreproducedViolation() throws {
        let original = try Self.run("original", plan: "plan", outcome: "violatedWithinScope")
        let passed = try Self.run("replay", plan: "plan", outcome: "holdsWithinScope")
        #expect(try ReplayComparison(original: original, replay: passed).jobs["a"] == "unreproduced")
        #expect(original.attempts[0].outcome == "violatedWithinScope")
        let repeated = try Self.run("repeated", plan: "plan", outcome: "violatedWithinScope")
        #expect(try ReplayComparison(original: original, replay: repeated).jobs["a"] == "reproduced")
        let incomplete = try Self.run("incomplete", plan: "plan", outcome: "notEvaluated", execution: "timeout")
        #expect(try ReplayComparison(original: original, replay: incomplete).jobs["a"] == "inconclusive")
        let otherInput = try Self.run("other", plan: "different", outcome: "violatedWithinScope")
        #expect(throws: (any Error).self) { try ReplayComparison(original: original, replay: otherInput) }
    }
    @Test(.timeLimit(.minutes(1))) func replayAssociationPersistsAcrossStoreReopen() async throws {
        let (store, plan, root) = try await SchedulerTests.setup(jobs: [SchedulerTests.job("a")])
        let old = try Self.run("original", plan: plan.id, outcome: "violatedWithinScope")
        let replay = try Self.run("replay", plan: plan.id, outcome: "holdsWithinScope")
        try await store.saveRun(old); try await store.saveRun(replay)
        try await store.saveReplay(originalRunID: old.id, replayRunID: replay.id)
        try await store.shutdown()
        let reopened = try SQLiteVerificationStore(root: root)
        #expect(try await reopened.loadReplay(replay.id)?.jobs["a"] == "unreproduced")
        #expect(try await reopened.loadRun(old.id) == old)
        try await reopened.shutdown(); try FileManager.default.removeItem(at: root)
    }
    @Test func differentNativeWitnessDoesNotReproduceTheOriginal() throws {
        func native(_ id: String, key: String?) -> VerificationRun {
            let evidence = VerificationEvidence(inputID: Canonical.digest(Data("native-fixture".utf8)),jobID: "fuzz", execution: "completed", outcome: "violatedWithinScope", domain: "nativeExecution", translation: "notApplicable", scope: "BOUNDED_SEEDED_NATIVE_INPUTS", adequacy: "completeWithinScope", detail: "fixture", diagnosticCode: "ORACLE_FALSE", startedAt: "now", finishedAt: "now", reproductionKey: key)
            return VerificationRun(id: id, planID: "same-plan", attempts: [evidence], accepted: false)
        }
        let original = native("original", key: String(repeating: "1", count: 64))
        #expect(try ReplayComparison(original: original, replay: native("repeat", key: original.attempts[0].reproductionKey)).jobs["fuzz"] == "reproduced")
        #expect(try ReplayComparison(original: original, replay: native("different", key: String(repeating: "2", count: 64))).jobs["fuzz"] == "unreproduced")
        #expect(try ReplayComparison(original: native("legacy", key: nil), replay: native("repeat", key: original.attempts[0].reproductionKey)).jobs["fuzz"] == "inconclusive")
    }

}
