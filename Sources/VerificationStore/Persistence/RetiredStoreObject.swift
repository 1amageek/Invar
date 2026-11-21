import Foundation
import VerificationCore

struct RetiredStoreObject: Codable, Sendable {
    let kind: String
    let id: String
    let relativePath: String
    var journalID: String { Canonical.parts("invar.deletion/2",[kind,id,relativePath]) }
    func validate() throws {
        _ = try Canonical.relative(relativePath)
        let parts = relativePath.split(separator: "/")
        guard parts.count == 2, ["inputs","prepared","artifacts","runs","preparing"].contains(String(parts[0])), parts[1] != ".." else { throw InvarError("STORE_INTEGRITY","Invalid retired Store path") }
        if kind != "orphan" { guard String(parts[1]) == id else { throw InvarError("STORE_INTEGRITY","Retirement object/path differs") }; try PlanValidation.identifier(id) }
    }
}
