import Foundation

public enum ConfigurationReader {
    public static func decode(_ bytes: Data) throws -> VerificationConfiguration {
        do { return try validated(bytes) }
        catch let error as InvarError { throw error }
        catch { throw invalid("Malformed JSON or configuration field type") }
    }
    private static func validated(_ bytes: Data) throws -> VerificationConfiguration {
        guard bytes.count <= 262144, var root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
            Set(root.keys).isSubset(of: ["schemaVersion", "architecture", "formal", "native", "fuzz", "project"]) else { throw invalid("Unknown fields or oversized configuration") }
        for name in ["architecture", "formal", "native", "fuzz"] {
            if root[name] == nil { root[name] = [[String: Any]]() }
            guard var entries = root[name] as? [[String: Any]] else { throw invalid("Expected an array for \(name)") }
            for index in entries.indices {
                var item = entries[index]
                let allowed: Set<String>
                switch name {
                case "architecture": allowed = ["id", "kind", "relations", "from", "to", "approved", "required"]
                case "formal": allowed = ["id", "source", "mode", "specification", "toolchain", "approved", "required", "acceptUnvalidatedModel", "memoryMiB"]
                case "native": allowed = ["id", "profile", "expectedTestCount", "expectedSignal", "approved", "required"]
                default: allowed = ["id", "profile", "corpus", "inputEncoding", "seed", "minimum", "maximum", "iterations", "approved", "required", "acceptNoViolationObservedWithinBudget"]
                }
                guard Set(item.keys).isSubset(of: allowed), let id = item["id"] as? String, !id.isEmpty, id.utf8.count <= 128,
                    id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 || $0 == 45 }) else { throw invalid("Unknown fields or unsafe check identifier") }
                item["approved"] = item["approved"] ?? false; item["required"] = item["required"] ?? true
                if name == "architecture" {
                    item["relations"] = item["relations"] ?? ["dependsOn", "imports", "calls"]
                    for key in ["from", "to"] where item[key] != nil {
                        guard let selector = item[key] as? [String: Any], !selector.isEmpty, Set(selector.keys).isSubset(of: ["id", "kind", "name", "pathPrefix"]), selector.values.allSatisfy({ ($0 as? String)?.isEmpty == false }) else { throw invalid("Invalid entity selector") }
                    }
                } else if name == "formal" {
                    item["acceptUnvalidatedModel"] = item["acceptUnvalidatedModel"] ?? false
                    if let raw = item["memoryMiB"] {
                        guard let memory = raw as? Int, (64...131072).contains(memory) else { throw invalid("Formal memoryMiB must be an integer from64 through131072") }
                    }
                }
                else {
                    guard var profile = item["profile"] as? [String: Any], Set(profile.keys).isSubset(of: ["kind", "compiler", "sdk", "toolsDirectory", "target", "modules", "harness"]) else { throw invalid("Invalid native profile") }
                    profile["kind"] = profile["kind"] ?? "swift-modules-json/1"; profile["target"] = profile["target"] ?? "arm64-apple-macosx27.0"
                    guard var modules = profile["modules"] as? [[String: Any]] else { throw invalid("Expected explicit native modules") }
                    for index in modules.indices {
                        guard Set(modules[index].keys).isSubset(of: ["name", "sources", "dependencies"]) else { throw invalid("Unknown native module field") }
                        modules[index]["dependencies"] = modules[index]["dependencies"] ?? [String]()
                    }
                    profile["modules"] = modules; item["profile"] = profile
                    if name == "native" { item["expectedTestCount"] = item["expectedTestCount"] ?? 1 }
                    else { item["inputEncoding"] = item["inputEncoding"] ?? "signed64-decimal"; item["acceptNoViolationObservedWithinBudget"] = item["acceptNoViolationObservedWithinBudget"] ?? false }
                }
                entries[index] = item
            }
            root[name] = entries
        }
        if let project = root["project"] {
            let required: Set<String> = ["id","subjectID","command","toolDigests","reportBuilder","report","contracts","budget","approved","required"]
            guard let fields = project as? [String:Any], required.isSubset(of: fields.keys),
                  Set(fields.keys).subtracting(required).isSubset(of: ["stage"]) else { throw invalid("Invalid project-command fields") }
        }
        let normalized = try JSONSerialization.data(withJSONObject: root)
        let value = try JSONDecoder().decode(VerificationConfiguration.self, from: normalized)
        let ids = value.architecture.map(\.id) + value.formal.map(\.id) + value.native.map(\.id) + value.fuzz.map(\.id) + (value.project.map { [$0.id] } ?? [])
        guard value.schemaVersion == 1, ids.count <= 500, Set(ids).count == ids.count else { throw invalid("Invalid schema, job count or duplicate identifiers") }
        try value.project?.validate()
        for policy in value.architecture {
            guard ["forbiddenDependency", "cycle"].contains(policy.kind), !policy.relations.isEmpty, policy.relations.allSatisfy({ !$0.isEmpty }),
                policy.kind != "forbiddenDependency" || (policy.from != nil && policy.to != nil) else { throw invalid("Invalid architecture policy") }
        }
        for check in value.formal {
            _ = try Canonical.relative(check.source); _ = try Canonical.relative(check.specification)
            guard ["finite", "quantified"].contains(check.mode), !check.toolchain.isEmpty, (64...131072).contains(check.admissionMemoryMiB) else { throw invalid("Invalid formal mode/toolchain") }
        }
        for check in value.native {
            try PlanValidation.profile(check.profile)
            guard (1...1000000).contains(check.expectedTestCount), (check.expectedSignal.map({ [4, 5, 6, 8, 10, 11].contains($0) && check.expectedTestCount == 1 }) ?? true) else { throw invalid("Invalid native oracle count/signal") }
        }
        for check in value.fuzz {
            try PlanValidation.profile(check.profile); _ = try Canonical.relative(check.corpus)
            guard check.inputEncoding == "signed64-decimal", UInt64(check.seed) != nil, let lower = Int64(check.minimum), let upper = Int64(check.maximum), lower <= upper,
                (1...1000).contains(check.iterations) else { throw invalid("Invalid bounded fuzz profile") }
        }
        return value
    }
    private static func invalid(_ message: String) -> InvarError { InvarError("INVALID_CONFIGURATION", message, exitCode: 2) }
}
