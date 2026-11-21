import ArchitectureCore
import Foundation
import Testing
import VerificationCore
@testable import VerificationExplorer

@Suite(.timeLimit(.minutes(1))) struct SwiftCallBindingsTests {
    @Test func onlyDirectCallsWithMatchingLabelsProducePinnedExpressionRanges() throws {
        let source = "func fits(_ started: Bool, before end: Bool) -> Bool { started && end }"
        let caller = """
        // fits(false, before: false)
        func use(_ é: Int) {
            if fits(check(é, 1), before: é < 3) { print("visible") }
            other.fits(true, before: true)
            fits(true, after: false)
        }
        """
        let data = Data(caller.utf8), digest = Canonical.digest(Data(source.utf8))
        let file = EntityRecord(id: "caller", kind: "file", language: "swift", name: "Caller.swift",
            path: "Caller.swift", sourceDigest: Canonical.digest(data))
        let inventory = ScopeInventory(workspaceID: "workspace", snapshotID: "snap", contextDigest: "context",
            metadata: [:], entities: [file], facts: [], coverage: [], inputs: [], diagnostics: [])
        let capture = CapturedWorkspace(inventory: inventory, files: ["F.swift": Data(source.utf8), "Caller.swift": data])
        let result = try SwiftCallBindings.resolve(entry: "fits", source: "F.swift", digest: digest, capture: capture)
        #expect(result["parameters"].array.compactMap(\.string) == ["started", "end"])
        #expect(result["sites"].array.count == 1)
        let site = try #require(result["sites"].array.first)
        #expect(site["ifCondition"].bool == true)
        let expressions = try site["arguments"].array.map { range in
            let start = try #require(range["start"].int), end = try #require(range["end"].int)
            return String(decoding: data[start..<end], as: UTF8.self)
        }
        #expect(expressions == ["check(é, 1)", "é < 3"])
        #expect(throws: InvarError.self) {
            try SwiftCallBindings.resolve(entry: "fits", source: "F.swift", digest: "wrong", capture: capture)
        }
    }
}
