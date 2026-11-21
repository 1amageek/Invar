import Foundation

public enum ProjectReportAssessment {
    public static func outcome(_ bytes: Data) throws -> String {
        guard let document = try JSONSerialization.jsonObject(with: bytes) as? [String:Any],
            let metadata = document["metadata"] as? [String:Any], let report = metadata["verificationReport"] as? [String:Any],
            report["schemaVersion"] as? Int == 2,
            let inventory = report["inventory"] as? [String], !inventory.isEmpty, inventory.count <= 450, inventory.allSatisfy({ !$0.isEmpty }), Set(inventory).count == inventory.count,
            let rows = report["requirements"] as? [[String:Any]], rows.count == inventory.count,
            Set(rows.compactMap { $0["id"] as? String }) == Set(inventory) else { throw InvarError("INVALID_RESULT","Project report lacks a complete unique acceptance inventory") }
        guard let rawClaims = report["evidence"] as? [[String:Any]], rawClaims.count <= 4096,
            let receipts = report["receipts"] as? [[String:Any]], !receipts.isEmpty,
            let production = report["productionInputs"] as? [[String:Any]] else { throw invalid("Project report omits evidence receipts or production inventory") }
        let receiptKeys = try referenceKeys(receipts), productionKeys = try referenceKeys(production)
        var claims: [String:[String:Any]] = [:]
        let methods = ["specificationCheck":["modelCheck","proof"],"implementationCheck":["modelCheck","proof"],"correspondenceCheck":["translationValidation"],"modelGeneration":["generation"],"regression":["test"]]
        for claim in rawClaims {
            guard let id = claim["id"] as? String, !id.isEmpty, claims[id] == nil,
                let requirements = claim["requirements"] as? [String], Set(requirements).count == requirements.count, Set(requirements).isSubset(of: Set(inventory)),
                let scope = claim["scope"] as? String, !scope.isEmpty,
                let outcome = claim["outcome"] as? String, outcomes.contains(outcome),
                let activity = claim["activity"] as? String, let method = claim["method"] as? String, methods[activity]?.contains(method) == true,
                let receipt = claim["receipt"] as? [String:Any], receiptKeys.contains(try referenceKey(receipt)) else { throw invalid("Claim lacks its original activity, scope or receipt") }
            if outcome == "passed", !["modelGeneration","regression"].contains(activity) {
                guard let obligations = claim["obligations"] as? [[String:Any]], !obligations.isEmpty, obligations.count <= 64 else { throw invalid("Passed formal claim lacks named obligations") }
                for obligation in obligations {
                    guard let selector = obligation["selector"] as? String, !selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalid("Missing named obligation selector") }
                    _ = try referenceKey(obligation)
                }
                if activity != "specificationCheck" {
                    guard let source = claim["sourceInputs"] as? [[String:Any]], let model = claim["modelInputs"] as? [[String:Any]] else { throw invalid("Passed claim lacks source/model binding") }
                    let sources = try referenceKeys(source), models = try referenceKeys(model)
                    guard !sources.isEmpty, !models.isEmpty, sources.isSubset(of: productionKeys), sources.isDisjoint(with: models) else { throw invalid("Passed claim differs from production/model inputs") }
                }
            }
            claims[id] = claim
        }
        var phaseValues = Dictionary(uniqueKeysWithValues: phases.map { ($0,[String]()) }), covered = Set<String>()
        for row in rows {
            guard let id = row["id"] as? String else { throw invalid("Missing requirement identity") }
            for phase in phases {
                guard let assessment = row[phase] as? [String:Any], let outcome = assessment["outcome"] as? String,
                    let references = assessment["claims"] as? [String], Set(references).count == references.count else { throw invalid("Project report omits a phase or its claims") }
                var values: [String] = []
                for reference in references {
                    guard let claim = claims[reference], let requirements = claim["requirements"] as? [String], requirements.contains(id),
                        let value = claim["outcome"] as? String, let activity = claim["activity"] as? String, let domain = claim["domain"] as? String else { throw invalid("Phase claim is absent or belongs to another requirement") }
                    let prefix = phase == "specification" ? domain.hasPrefix("specification.") : phase == "implementation" ? domain.hasPrefix("generatedModel.") || domain.hasPrefix("source.") : domain == "translation.validated" || value != "passed" && domain.hasPrefix("translation.")
                    let expected = phase == "specification" ? "specificationCheck" : phase == "implementation" ? "implementationCheck" : "correspondenceCheck"
                    guard prefix, activity == expected || phase == "implementation" && activity == "modelGeneration" && value != "passed" else { throw invalid("Generation/regression or another domain cannot establish this formal phase") }
                    values.append(value)
                    if phase == "implementation", value == "passed", let source = claim["sourceInputs"] as? [[String:Any]] { covered.formUnion(try referenceKeys(source)) }
                }
                guard aggregate(values) == outcome else { throw invalid("Phase verdict disagrees with its original claims") }
                phaseValues[phase]!.append(outcome)
            }
            if (row["correspondence"] as? [String:Any])?["outcome"] as? String == "passed" {
                for field in ["sourceInputs","modelInputs"] {
                    var bound: [Set<String>] = []
                    for phase in ["implementation","correspondence"] {
                        guard let assessment = row[phase] as? [String:Any], let ids = assessment["claims"] as? [String] else { throw invalid("Missing correspondence assessment") }
                        var inputs = Set<String>()
                        for id in ids { if let values = claims[id]?[field] as? [[String:Any]] { inputs.formUnion(try referenceKeys(values)) } }
                        bound.append(inputs)
                    }
                    guard !bound[0].isEmpty, bound[0] == bound[1] else { throw invalid("Correspondence differs from the checked source/model binding") }
                }
            }
        }
        let outcome = try ProjectWorkflowAssessment.outcome(report: report,inventory: Set(inventory),phaseValues: phaseValues,production: productionKeys,covered: covered)
        guard report["outcome"] as? String == outcome else { throw InvarError("INVALID_RESULT","Project verdict disagrees with its complete assessments") }
        return outcome
    }
    static let phases = ["specification","implementation","correspondence"]
    static let outcomes = ["passed","failed","unsupported","unknown","notVerified"]
    static func aggregate(_ values: [String]) -> String {
        for value in ["failed","unsupported","unknown","notVerified"] where values.contains(value) { return value }
        return values.isEmpty ? "notVerified" : "passed"
    }
    static func referenceKey(_ reference: [String:Any]) throws -> String {
        guard let path = reference["path"] as? String, let digest = reference["sha256"] as? String,
            digest.utf8.count == 64, digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw invalid("Missing exact evidence reference") }
        _ = try Canonical.relative(path)
        return path + "\0" + digest
    }
    static func referenceKeys(_ references: [[String:Any]]) throws -> Set<String> {
        guard references.count <= 4096 else { throw invalid("Evidence reference count exceeds its bound") }
        let keys = try references.map(referenceKey)
        guard Set(keys).count == keys.count else { throw invalid("Duplicate evidence reference") }
        return Set(keys)
    }
    static func invalid(_ message: String) -> InvarError { InvarError("INVALID_RESULT",message) }
}
