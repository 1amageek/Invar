import Foundation
import Testing
import VerificationCore
import VerificationDiscovery

@Suite(.timeLimit(.minutes(1)))
struct ChangeTrackingTests {
    let budget = ChangeAnalysisBudget(maximumFiles: 100,maximumBytes: 1_048_576,maximumRecords: 1000,maximumVisits: 1000,maximumOutputBytes: 262_144)
    func capture(_ files: [String:Data],snapshot: String,complete: Bool = true,context: String = "context",facts: [FactRecord] = []) -> CapturedWorkspace {
        let inputs = files.sorted { $0.key < $1.key }.map { InputEntry(path: $0.key,digest: Canonical.digest($0.value),byteCount: $0.value.count) }
        let entities = inputs.map { EntityRecord(id: $0.path,kind: "file",language: "swift",name: $0.path,path: $0.path,sourceDigest: $0.digest,startByte: 0,endByte: $0.byteCount) }
        let inventory = ScopeInventory(workspaceID: "workspace",snapshotID: snapshot,contextDigest: context,metadata: ["dependencyStatus":complete ? "completeWithinScope" : "unknown"],entities: entities,facts: facts,coverage: [CoverageRecord(producer: "test",scope: "workspace",freshness: "current",completeness: complete ? "completeWithinScope" : "partial")],inputs: inputs)
        return CapturedWorkspace(inventory: inventory,files: files)
    }
    func request(_ before: CapturedWorkspace,_ after: CapturedWorkspace,claim: ChangeClaim? = nil,overlaps: [ChangeOverlap] = [],oraclePaths: [String] = []) -> ChangeAnalysisRequest {
        ChangeAnalysisRequest(before: before,after: after,claim: claim,overlaps: overlaps,oraclePaths: oraclePaths,impactRelations: ["calls","dependsOn"],budget: budget)
    }
    @Test func unicodeEnclosingHunkHasExactByteAndLineBoundaries() throws {
        let a = Data("one\nα\nlast\n".utf8), b = Data("one\nβ\nlast\n".utf8)
        let result = try ExactChangeAnalyzer().analyze(request(capture(["file.swift":a],snapshot: "old"),capture(["file.swift":b],snapshot: "new")))
        let hunk = try #require(result.delta.files.first?.hunks.first)
        let old = try #require(hunk.before), new = try #require(hunk.after)
        #expect(old.start == 4 && old.end == 6 && old.startLine == 2 && old.endLine == 2)
        #expect(String(data: a.subdata(in: old.start..<old.end),encoding: .utf8) == "α")
        #expect(String(data: b.subdata(in: new.start..<new.end),encoding: .utf8) == "β")
        #expect(result.attribution.kind == "external")
    }
    @Test func exactMovesRequireUniqueContentAndDeletedSubjectsRemainHistorical() throws {
        let data = Data("same".utf8)
        let unique = try ExactChangeAnalyzer().analyze(request(capture(["a.swift":data],snapshot: "old"),capture(["b.swift":data],snapshot: "new")))
        #expect(unique.correspondences.count == 1)
        #expect(unique.correspondences.first?.before.snapshotID == "old" && unique.correspondences.first?.before.path == "a.swift")
        let ambiguous = try ExactChangeAnalyzer().analyze(request(capture(["a.swift":data,"b.swift":data],snapshot: "old"),capture(["b.swift":data,"c.swift":data],snapshot: "new")))
        #expect(ambiguous.correspondences.isEmpty)
        #expect(ambiguous.delta.unknownBoundaries.contains { $0.contains("Ambiguous") })
        #expect(ambiguous.delta.files.contains { $0.kind == "removed" && $0.path == "a.swift" })
    }
    @Test func overlappingAgentAndUserEditsDoNotBecomeExclusiveAuthorship() throws {
        let a = Data("old".utf8), b = Data("new".utf8)
        let claim = ChangeClaim(intent: "Update algorithm",paths: ["agent.swift"],entityIDs: [],patchDigest: nil,expectedFiles: [ClaimedFileState(path: "agent.swift",digest: Canonical.digest(b))])
        let before = capture(["agent.swift":a,"user.swift":a],snapshot: "old"), after = capture(["agent.swift":b,"user.swift":b],snapshot: "new")
        let result = try ExactChangeAnalyzer().analyze(request(before,after,claim: claim,overlaps: [ChangeOverlap(changeID: "another-agent",paths: ["agent.swift"])]))
        #expect(result.attribution.kind == "overlapping")
        #expect(result.attribution.overlappingChangeIDs == ["another-agent"] && result.attribution.unclaimedPaths == ["user.swift"])
        #expect(result.attribution.basis.contains { $0.contains("No exclusive") })
    }
    @Test func reverseImpactAndUnknownClosurePreserveDifferentCoverage() throws {
        let facts = [FactRecord(id: "call",kind: "calls",source: "caller.swift",target: "callee.swift",producer: "test",scope: "workspace")]
        let old = ["callee.swift":Data("old".utf8),"caller.swift":Data("call".utf8),"unrelated.swift":Data("other".utf8)]
        var new = old; new["callee.swift"] = Data("new".utf8)
        let precise = try ExactChangeAnalyzer().analyze(request(capture(old,snapshot: "old",facts: facts),capture(new,snapshot: "new",facts: facts)))
        #expect(precise.impactComplete && precise.impactEntityIDs == ["callee.swift","caller.swift"])
        let uncertain = try ExactChangeAnalyzer().analyze(request(capture(old,snapshot: "old",complete: false,facts: facts),capture(new,snapshot: "new",complete: false,facts: facts)))
        #expect(!uncertain.impactComplete && uncertain.impactEntityIDs.count == 3)
        #expect(!uncertain.delta.unknownBoundaries.isEmpty)
    }
    @Test func tamperedFixedInputsFailAndBinaryDeletionRetainsExactRegion() throws {
        let bytes = Data([0,255,1]), captured = capture(["input.bin":bytes],snapshot: "old")
        let removed = try ExactChangeAnalyzer().analyze(request(captured,capture([:],snapshot: "new")))
        let hunk = try #require(removed.delta.files.first?.hunks.first)
        #expect(hunk.encoding == "binary" && hunk.before?.start == 0 && hunk.before?.end == 3 && hunk.after == nil && hunk.before?.startLine == nil)
        let changed = CapturedWorkspace(inventory: captured.inventory,files: ["input.bin":Data([1])])
        #expect(throws: InvarError.self) { try ExactChangeAnalyzer().analyze(request(changed,capture([:],snapshot: "new"))) }
    }
}
