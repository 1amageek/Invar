import Foundation

/// Recomputes reviewed gate progression independently of display labels.
enum ProjectWorkflowAssessment {
    static func outcome(report: [String:Any],inventory: Set<String>,phaseValues: [String:[String]],production: Set<String>,covered: Set<String>) throws -> String {
        let order = ["requirements","specification","implementation","correspondence","integration"]
        guard let workflow = report["workflow"] as? [String:Any], workflow["schemaVersion"] as? Int == 1,
            let stages = workflow["stages"] as? [[String:Any]], stages.compactMap({ $0["id"] as? String }) == order,
            let reviews = workflow["reviews"] as? [[String:Any]], reviews.count <= inventory.count * order.count,
            let architecture = report["architectureInputs"] as? [[String:Any]],
            workflow["productionInputCount"] as? Int == production.count,
            workflow["coveredProductionInputCount"] as? Int == production.intersection(covered).count else { throw ProjectReportAssessment.invalid("Project workflow omits reviewed gates or production coverage") }
        let architectureKeys = try ProjectReportAssessment.referenceKeys(architecture)
        let architecturePaths = Set(architecture.compactMap { $0["path"] as? String })
        guard architecture.isEmpty || architecturePaths.contains("ARCHITECTURE.dsl") && architecturePaths.count == architecture.count && architecturePaths.allSatisfy({ $0.hasSuffix(".dsl") }) else {
            throw ProjectReportAssessment.invalid("Architecture inputs omit the root ARCHITECTURE.dsl or contain invalid fragments")
        }
        var accepted = Dictionary(uniqueKeysWithValues: order.map { ($0,Set<String>()) }), occupied = Set<String>(), requested = Set<String>()
        for review in reviews {
            guard review["schemaVersion"] as? Int == 1, let stage = review["stage"] as? String, order.contains(stage),
                let requirements = review["requirements"] as? [String], !requirements.isEmpty, Set(requirements).count == requirements.count, Set(requirements).isSubset(of: inventory),
                let decision = review["decision"] as? String, ["passed","changesRequested","incomplete"].contains(decision),
                let summary = review["summary"] as? String, !summary.isEmpty, let findings = review["findings"] as? [[String:Any]],
                let reference = review["reference"] as? [String:Any], let inputs = review["inputs"] as? [[String:Any]], !inputs.isEmpty,
                let complete = review["bindingComplete"] as? Bool else { throw ProjectReportAssessment.invalid("Stage review lacks a current evidence binding") }
            _ = try ProjectReportAssessment.referenceKey(reference)
            let inputKeys = try ProjectReportAssessment.referenceKeys(inputs)
            if complete, stage == "requirements" || stage == "integration" {
                guard architectureKeys.isSubset(of: inputKeys) else { throw ProjectReportAssessment.invalid("Review omits the exact architecture inputs") }
            }
            for id in requirements { guard occupied.insert(stage + "\0" + id).inserted else { throw ProjectReportAssessment.invalid("Ambiguous overlapping stage reviews") } }
            guard decision != "passed" || findings.isEmpty, decision != "changesRequested" || !findings.isEmpty else { throw ProjectReportAssessment.invalid("Review decision and findings disagree") }
            for finding in findings {
                guard let id = finding["requirementID"] as? String, requirements.contains(id), let target = finding["returnTo"] as? String,
                    let targetIndex = order.firstIndex(of: target), let sourceIndex = order.firstIndex(of: stage), targetIndex <= sourceIndex,
                    let reason = finding["reason"] as? String, !reason.isEmpty else { throw ProjectReportAssessment.invalid("Finding lacks its owning return stage") }
                requested.insert(target)
            }
            let intentComplete = stage == "requirements" ? try resolvedIntent(review, requirements: Set(requirements)) : true
            guard review["intentComplete"] as? Bool == intentComplete else {
                throw ProjectReportAssessment.invalid("Requirements review disagrees with its recorded intent")
            }
            if decision == "passed", complete, intentComplete { accepted[stage]!.formUnion(requirements) }
        }
        let phaseOutcomes = ProjectReportAssessment.phases.map { ProjectReportAssessment.aggregate(phaseValues[$0]!) }
        var evidence = Dictionary(uniqueKeysWithValues: zip(ProjectReportAssessment.phases,phaseOutcomes))
        evidence["requirements"] = architecture.isEmpty ? "notVerified" : "passed"
        evidence["integration"] = ProjectReportAssessment.aggregate(phaseOutcomes)
        if production.isEmpty || !production.isSubset(of: covered) {
            for id in ["implementation","integration"] where evidence[id] == "passed" { evidence[id] = "unknown" }
        }
        var blocked = false, returns = requested, allPassed = true
        for (index,id) in order.enumerated() {
            let review = accepted[id] == inventory ? "passed" : "incomplete"
            let own = evidence[id] == "failed" ? "failed" : evidence[id] == "passed" && review == "passed" && !requested.contains(id) ? "passed" : "incomplete"
            let expected = blocked ? "blocked" : own
            guard stages[index]["status"] as? String == expected, stages[index]["evidence"] as? String == evidence[id],
                stages[index]["review"] as? String == review else { throw ProjectReportAssessment.invalid("Workflow gate disagrees with evidence, reviews or prerequisites") }
            if own != "passed" { returns.insert(id); blocked = true }
            allPassed = allPassed && expected == "passed"
        }
        let expectedReturn = order.first { returns.contains($0) }
        guard workflow["returnTo"] as? String == expectedReturn else { throw ProjectReportAssessment.invalid("Workflow return stage differs from the earliest unmet contract") }
        let result = phaseOutcomes.contains("failed") ? "failed" : allPassed ? "passed" : "incomplete"
        guard workflow["outcome"] as? String == result else { throw ProjectReportAssessment.invalid("Workflow verdict disagrees with reviewed gates") }
        return result
    }

    private static func resolvedIntent(_ review: [String:Any], requirements: Set<String>) throws -> Bool {
        guard let value = review["intent"] else { return false }
        guard let entries = value as? [[String:Any]] else {
            throw ProjectReportAssessment.invalid("Invalid requirements intent")
        }
        var seen = Set<String>()
        var resolved = Set<String>()
        for entry in entries {
            guard let id = entry["requirementID"] as? String, requirements.contains(id), seen.insert(id).inserted,
                let basis = entry["basis"] as? String, ["request", "existingSpecification", "userDecision", "pending"].contains(basis),
                ["decision", "rationale", "source"].allSatisfy({
                    guard let text = entry[$0] as? String else { return false }
                    return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }) else {
                throw ProjectReportAssessment.invalid("Intent lacks a unique requirement, decision, rationale or authority")
            }
            if basis != "pending" { resolved.insert(id) }
        }
        return resolved == requirements
    }
}
