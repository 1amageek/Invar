import Foundation
import VerificationCore

public struct ArchitectureRuleEvaluator: ArchitecturePolicyEvaluating {
    public init() {}
    private func matches(_ selector: EntitySelector, _ entity: EntityRecord) -> Bool {
        (selector.id == nil || selector.id == entity.id) && (selector.kind == nil || selector.kind == entity.kind)
            && (selector.name == nil || selector.name == entity.name)
            && (selector.pathPrefix == nil || entity.path.map { $0 == selector.pathPrefix! || $0.hasPrefix(selector.pathPrefix! + "/") } == true)
    }
    public func evaluate(_ policy: ArchitecturePolicy, inventory: ScopeInventory) throws -> VerificationEvidence {
        guard Set(inventory.entities.map(\.id)).count == inventory.entities.count,
            Set(inventory.facts.map(\.id)).count == inventory.facts.count else { throw InvarError("INVALID_GRAPH", "Duplicate graph identities") }
        let ids = Set(inventory.entities.map(\.id))
        guard inventory.facts.allSatisfy({ ids.contains($0.source) && ids.contains($0.target) }) else { throw InvarError("INVALID_GRAPH", "Dangling fact endpoint") }
        let started = Canonical.date(), nodes = Dictionary(uniqueKeysWithValues: inventory.entities.map { ($0.id, $0) })
        let facts = inventory.facts.filter { policy.relations.contains($0.kind) }
        var witness: [FactRecord] = [], nonvacuous = false
        if policy.kind == "forbiddenDependency" {
            guard let from = policy.from, let to = policy.to else { throw InvarError("INVALID_POLICY", "Forbidden dependency requires both selectors", exitCode: 2) }
            nonvacuous = inventory.entities.contains { matches(from, $0) } && inventory.entities.contains { matches(to, $0) }
            witness = facts.filter { edge in nodes[edge.source].map { matches(from, $0) } == true && nodes[edge.target].map { matches(to, $0) } == true }
        } else if policy.kind == "cycle" {
            let selected = Set(inventory.entities.filter { node in policy.from.map { matches($0, node) } ?? true }.map(\.id))
            nonvacuous = !selected.isEmpty
            let edges = facts.filter { selected.contains($0.source) && selected.contains($0.target) }
            let adjacency = Dictionary(grouping: edges.sorted { $0.id < $1.id }, by: \.source)
            var color: [String: Int] = [:], parents: [String: FactRecord] = [:]
            outer: for root in selected.sorted() where color[root] == nil {
                color[root] = 1; var stack: [(String, Int)] = [(root, 0)]
                while let (node, index) = stack.last {
                    let outgoing = adjacency[node, default: []]
                    if index >= outgoing.count { color[node] = 2; stack.removeLast(); continue }
                    stack[stack.count - 1].1 += 1
                    let edge = outgoing[index]
                    if color[edge.target] == 1 {
                        witness = [edge]; var cursor = node
                        while cursor != edge.target, let parent = parents[cursor] { witness.append(parent); cursor = parent.source }
                        break outer
                    }
                    if color[edge.target] == nil { parents[edge.target] = edge; color[edge.target] = 1; stack.append((edge.target, 0)) }
                }
            }
        } else { throw InvarError("UNSUPPORTED_POLICY", "Unknown architecture policy kind", exitCode: 3) }
        let complete = nonvacuous && !inventory.coverage.isEmpty && inventory.coverage.allSatisfy { $0.freshness == "current" && $0.completeness == "completeWithinScope" && $0.exclusions.isEmpty }
        let witnessCurrent = !witness.isEmpty && witness.allSatisfy { edge in
            let coverage = inventory.coverage.filter { $0.producer == edge.producer && ($0.scope == edge.scope || $0.scope == "workspace") }
            return !coverage.isEmpty && coverage.allSatisfy { $0.freshness == "current" }
        }
        let outcome = !witness.isEmpty ? "violatedWithinScope" : (complete ? "holdsWithinScope" : "unknown")
        let inputID = try Canonical.identity(inventory)
        return VerificationEvidence(inputID: inputID,jobID: policy.id, execution: "completed", outcome: outcome, domain: "architecture", translation: "notApplicable",
            scope: "Recorded \(policy.relations.joined(separator: ",")) facts in snapshot \(inventory.snapshotID)",
            adequacy: complete ? "completeWithinScope" : witnessCurrent ? "witnessWithinScope" : "unknown",
            detail: !witness.isEmpty ? "Declared architecture policy has an exact recorded edge witness; this is not a runtime defect claim." : (complete ? "No policy violation in the declared complete recorded scope." : "No witness found; empty target, incomplete or stale coverage prevents an absence conclusion."),
            witnessFactIDs: witness.map(\.id).sorted(), startedAt: started, finishedAt: Canonical.date())
    }
}
