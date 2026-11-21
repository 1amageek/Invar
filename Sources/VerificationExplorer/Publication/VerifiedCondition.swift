import ArchitectureCore
import FormalEvidence
import Foundation
import VerificationCore

/// Projects authored conditions from the checked claim, independently of job and graph titles.
enum VerifiedCondition {
    private struct Quantified: Decodable {
        let name, entry, requires, ensures: String
    }
    private struct Finite: Decodable {
        struct Expected: Decodable { let status: String }
        let name, entry: String
        let expected: Expected
    }

    static func record(_ claim: VerificationClaim, bundleID: String) throws -> JSONValue? {
        var fields: [String: JSONValue] = [
            "claimID": .string(claim.id), "bundleID": .string(bundleID),
            "name": .string(claim.obligation), "domain": .string(claim.domain),
            "outcome": .string(claim.outcome), "scope": .string(claim.scope),
            "translation": .string(claim.translation)
        ]
        let bytes = Data(claim.proposition.utf8)
        let name: String
        switch claim.domain {
        case "generatedModel.lean.quantified":
            let property = try JSONDecoder().decode(Quantified.self, from: bytes)
            name = property.name
            fields["entry"] = .string(property.entry)
            fields["requires"] = .string(property.requires)
            fields["ensures"] = .string(property.ensures)
        case "generatedModel.tla.finite", "generatedModel.lean.finite":
            let scenario = try JSONDecoder().decode(Finite.self, from: bytes)
            name = scenario.name
            fields["entry"] = .string(scenario.entry)
            fields["expectedStatus"] = .string(scenario.expected.status)
        default:
            return nil
        }
        guard name == claim.obligation else {
            throw InvarError("INVALID_FORMAL_CLAIM", "Condition and obligation identities differ")
        }
        return .object(fields)
    }
}
