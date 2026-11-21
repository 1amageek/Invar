import Foundation
import Testing
import VerificationCore
@testable import VerificationBackends

struct SwiftExpressionSelectionTests {
    @Test func selectedTypeRetainsExactSitesAndExcludesSiblingAndFrameworkCalls() throws {
        let source = """
        // 日本語 changes UTF-8 offsets. x / 0
        struct Rows {
          func layout(_ items: [Int], height: Double) -> Double {
            if items.count > 0 { return height / Double(items.count / 7) }
            return 0
          }
        }
        struct Other { func bad(_ x: Int) -> Int { x / 0 } }
        """
        let bytes = Data(source.utf8)
        let end = try #require(bytes.range(of: Data("struct Other".utf8))).lowerBound
        let sites = try SwiftExpressionSelection.extract(bytes, path: "Rows.swift", selection: 0..<end)
        #expect(sites.map { String(decoding: bytes[$0.bytes], as: UTF8.self) } == ["items.count > 0","items.count / 7"])
        #expect(sites.last?.localCheck == "No arithmetic trap")
        guard case .conditional(false, .comparison(.count,.greater,.integer(0))) = sites.first?.expression else { Issue.record("Missing modeled comparison"); return }
        let sibling = try SwiftExpressionSelection.extract(bytes, path: "Rows.swift", selection: end..<bytes.count)
        #expect(sibling.map(\.localCheck) == ["Always traps"])
    }
    @Test func floatingPointDivisionAndUntypedMembersHaveNoIntegerTrapVerdict() throws {
        let source = "struct Floating { func f(_ x: Double) -> Double { x / 0 } }"
        let bytes = Data(source.utf8)
        #expect(throws: InvarError.self) { try SwiftExpressionSelection.extract(bytes,path: "Float.swift",selection: 0..<bytes.count) }
    }
    @Test func rejectsInvalidSyntaxAndEmptySelections() throws {
        for source in ["struct Bad {", "struct Empty { let text = \"a / 0\" }"] {
            let bytes = Data(source.utf8)
            #expect(throws: InvarError.self) { try SwiftExpressionSelection.extract(bytes,path: "Input.swift",selection: 0..<bytes.count) }
        }
    }
}
