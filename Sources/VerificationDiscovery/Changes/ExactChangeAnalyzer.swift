import Foundation
import VerificationCore

public struct ExactChangeAnalyzer: ChangeAnalyzing {
    public init() {}
    public func analyze(_ request: ChangeAnalysisRequest) throws -> ChangeAnalysis {
        let budget = request.budget
        guard budget.maximumFiles > 0, budget.maximumBytes > 0, budget.maximumRecords > 0, budget.maximumVisits > 0, budget.maximumOutputBytes > 0 else { throw InvarError("RESOURCE_LIMIT","Invalid change-analysis budget",exitCode: 6) }
        guard request.before.inventory.workspaceID == request.after.inventory.workspaceID else { throw InvarError("INPUT_MISMATCH","Changes must compare the same workspace") }
        try validate(request.before,budget: budget); try validate(request.after,budget: budget)
        let before = Dictionary(uniqueKeysWithValues: request.before.inventory.inputs.map { ($0.path,$0) })
        let after = Dictionary(uniqueKeysWithValues: request.after.inventory.inputs.map { ($0.path,$0) })
        var files: [FileChange] = []
        for path in Set(before.keys).union(after.keys).sorted() {
            try Task.checkCancellation()
            if before[path] == after[path] { continue }
            let old = request.before.files[path], new = request.after.files[path]
            let hunk = hunk(before: old,after: new)
            files.append(FileChange(path: path,kind: old == nil ? "added" : new == nil ? "removed" : "modified",before: before[path],after: after[path],hunks: [hunk]))
        }
        var differences: [RecordDifference] = []
        differences.append(try difference("entities",before: request.before.inventory.entities,after: request.after.inventory.entities,key: { $0.id }))
        differences.append(try difference("facts",before: request.before.inventory.facts,after: request.after.inventory.facts,key: { $0.id }))
        let rawBefore = request.before.inventory.originalRecords, rawAfter = request.after.inventory.originalRecords
        for category in Set(rawBefore.keys).union(rawAfter.keys).sorted() {
            let old = Set(rawBefore[category,default: []].map(Canonical.digest)), new = Set(rawAfter[category,default: []].map(Canonical.digest))
            if old != new { differences.append(RecordDifference(category: "raw:" + category,added: new.subtracting(old).sorted(),removed: old.subtracting(new).sorted(),changed: [])) }
        }
        let contextChanged = request.before.inventory.contextDigest != request.after.inventory.contextDigest || request.before.inventory.metadata != request.after.inventory.metadata || request.before.inventory.coverage != request.after.inventory.coverage
        let paths = Set(files.map(\.path))
        let overlapIDs = request.overlaps.filter { !paths.isDisjoint(with: Set($0.paths)) }.map(\.changeID).sorted()
        let attribution = try attribution(request.claim,files: files,after: after,overlapIDs: overlapIDs)
        var boundaries: [String] = []
        let oldGroups = Dictionary(grouping: before.values,by: \.digest), newGroups = Dictionary(grouping: after.values,by: \.digest)
        var correspondences: [SubjectCorrespondence] = []
        for file in files where file.kind == "removed" {
            guard let old = file.before else { continue }
            let candidates = files.filter { $0.kind == "added" && $0.after?.digest == old.digest }
            if candidates.isEmpty { continue }
            guard oldGroups[old.digest]?.count == 1, newGroups[old.digest]?.count == 1, candidates.count == 1, let moved = candidates.first?.after else {
                boundaries.append("Ambiguous exact-content move: " + file.path); continue
            }
            let oldSubject = subject(request.before.inventory,entry: old), newSubject = subject(request.after.inventory,entry: moved)
            correspondences.append(SubjectCorrespondence(before: oldSubject,after: newSubject,producer: "invar.exact-diff/1",basis: "Unique complete-manifest content digest",precision: "exactContentMove"))
        }
        let inventories = [request.before.inventory,request.after.inventory]
        let allEntities = inventories.flatMap(\.entities), allFacts = inventories.flatMap(\.facts)
        let allIDs = Set(allEntities.map(\.id))
        var impact = Set(allEntities.filter { $0.path.map(paths.contains) ?? false }.map(\.id))
        for difference in differences where difference.category == "entities" { impact.formUnion(difference.added + difference.removed + difference.changed) }
        let knownClosure = inventories.allSatisfy { inventory in
            inventory.metadata["dependencyStatus"] == "completeWithinScope" && !inventory.coverage.isEmpty && inventory.coverage.allSatisfy { $0.freshness == "current" && $0.completeness == "completeWithinScope" && $0.exclusions.isEmpty }
        }
        if !knownClosure { boundaries.append("Project dependency closure is unknown or incomplete") }
        let relations = Set(request.impactRelations)
        let reverse = Dictionary(grouping: allFacts.filter { relations.contains($0.kind) },by: \.target)
        var pending = impact.sorted(), index = 0, visits = 0, complete = knownClosure
        while index < pending.count {
            let id = pending[index]; index += 1
            for fact in reverse[id,default: []] {
                visits += 1
                if visits > budget.maximumVisits { complete = false; boundaries.append("Impact traversal budget exhausted"); break }
                if impact.insert(fact.source).inserted { pending.append(fact.source) }
            }
            if visits > budget.maximumVisits { break }
        }
        if contextChanged { complete = false; boundaries.append("Context, coverage or oracle environment changed") }
        if !complete {
            guard allIDs.count <= budget.maximumRecords else { throw InvarError("RESOURCE_LIMIT","Conservative enclosing impact exceeds result budget",exitCode: 6) }
            impact.formUnion(allIDs)
        }
        let delta = ObservedDelta(files: files,records: differences.filter { !$0.added.isEmpty || !$0.removed.isEmpty || !$0.changed.isEmpty },contextChanged: contextChanged,oraclePaths: request.oraclePaths.filter(paths.contains).sorted(),unknownBoundaries: Array(Set(boundaries)).sorted())
        let result = ChangeAnalysis(delta: delta,correspondences: correspondences,attribution: attribution,impactEntityIDs: impact.sorted(),impactComplete: complete)
        let bytes = try Canonical.encode(result)
        guard bytes.count <= budget.maximumOutputBytes else { throw InvarError("RESOURCE_LIMIT","Change analysis exceeds output budget",exitCode: 6) }
        return result
    }
    private func validate(_ capture: CapturedWorkspace,budget: ChangeAnalysisBudget) throws {
        let inventory = capture.inventory
        guard inventory.inputs.count <= budget.maximumFiles, Set(inventory.inputs.map(\.path)).count == inventory.inputs.count, Set(inventory.entities.map(\.id)).count == inventory.entities.count, Set(inventory.facts.map(\.id)).count == inventory.facts.count,
            inventory.entities.count <= budget.maximumRecords, inventory.facts.count <= budget.maximumRecords - inventory.entities.count,
            Set(inventory.inputs.map(\.path)) == Set(capture.files.keys) else { throw InvarError("INPUT_MISMATCH","Invalid or incomplete fixed snapshot") }
        var total = 0, records = inventory.entities.count + inventory.facts.count
        for file in inventory.inputs {
            _ = try Canonical.relative(file.path)
            guard let bytes = capture.files[file.path], file.byteCount == bytes.count, Canonical.digest(bytes) == file.digest else { throw InvarError("INPUT_MISMATCH","Fixed source manifest differs from original bytes") }
            guard bytes.count <= budget.maximumBytes - total else { throw InvarError("RESOURCE_LIMIT","Fixed snapshot byte budget exceeded",exitCode: 6) }
            total += bytes.count
        }
        for values in inventory.originalRecords.values {
            guard values.count <= budget.maximumRecords - records else { throw InvarError("RESOURCE_LIMIT","Raw snapshot record budget exceeded",exitCode: 6) }; records += values.count
            for bytes in values {
                guard bytes.count <= budget.maximumBytes - total else { throw InvarError("RESOURCE_LIMIT","Snapshot bytes exceed analysis budget",exitCode: 6) }; total += bytes.count
            }
        }
        let ids = Set(inventory.entities.map(\.id))
        guard inventory.facts.allSatisfy({ ids.contains($0.source) && ids.contains($0.target) }) else { throw InvarError("INPUT_MISMATCH","Dangling raw snapshot fact") }
    }
    private func difference<Value: Encodable>(_ category: String,before: [Value],after: [Value],key: (Value) -> String) throws -> RecordDifference {
        var old: [String:String] = [:], new: [String:String] = [:]
        for value in before { let digest = try Canonical.identity(value); old[key(value)] = digest }
        for value in after { let digest = try Canonical.identity(value); new[key(value)] = digest }
        let a = Set(old.keys), b = Set(new.keys)
        return RecordDifference(category: category,added: b.subtracting(a).sorted(),removed: a.subtracting(b).sorted(),changed: a.intersection(b).filter { old[$0] != new[$0] }.sorted())
    }
    private func hunk(before: Data?,after: Data?) -> FileHunk {
        let old = before ?? Data(), new = after ?? Data()
        let utf8 = String(data: old,encoding: .utf8) != nil && String(data: new,encoding: .utf8) != nil
        var prefix = 0
        while prefix < min(old.count,new.count), byte(old,prefix) == byte(new,prefix) { prefix += 1 }
        if utf8 { while prefix > 0 && (continuation(old,prefix) || continuation(new,prefix)) { prefix -= 1 } }
        var suffix = 0
        while suffix < min(old.count - prefix,new.count - prefix), byte(old,old.count - suffix - 1) == byte(new,new.count - suffix - 1) { suffix += 1 }
        if utf8 { while suffix > 0 && (continuation(old,old.count - suffix) || continuation(new,new.count - suffix)) { suffix -= 1 } }
        func region(_ bytes: Data) -> ByteRegion {
            ByteRegion(start: prefix,end: bytes.count - suffix,startLine: utf8 ? line(bytes,prefix) : nil,endLine: utf8 ? line(bytes,bytes.count - suffix) : nil)
        }
        return FileHunk(before: before == nil ? nil : region(old),after: after == nil ? nil : region(new),encoding: utf8 ? "utf8" : "binary")
    }
    private func byte(_ bytes: Data,_ offset: Int) -> UInt8 { bytes[bytes.startIndex + offset] }
    private func continuation(_ bytes: Data,_ offset: Int) -> Bool { offset < bytes.count && byte(bytes,offset) & 0xc0 == 0x80 }
    private func line(_ bytes: Data,_ offset: Int) -> Int { bytes.prefix(offset).reduce(1) { $1 == 10 ? $0 + 1 : $0 } }
    private func subject(_ inventory: ScopeInventory,entry: InputEntry) -> SubjectReference {
        SubjectReference(workspaceID: inventory.workspaceID,snapshotID: inventory.snapshotID,entityID: nil,factID: nil,path: entry.path,digest: entry.digest,range: nil)
    }
    private func attribution(_ claim: ChangeClaim?,files: [FileChange],after: [String:InputEntry],overlapIDs: [String]) throws -> AttributionAssessment {
        guard let claim else { return AttributionAssessment(kind: "external",basis: ["No registered Agent claim; authorship is unknown"],overlappingChangeIDs: overlapIDs,unclaimedPaths: files.map(\.path)) }
        guard Set(claim.paths).count == claim.paths.count, Set(claim.expectedFiles.map(\.path)).count == claim.expectedFiles.count else { throw InvarError("INVALID_CLAIM","Duplicate claim paths") }
        for path in claim.paths { _ = try Canonical.relative(path) }
        for expected in claim.expectedFiles { _ = try Canonical.relative(expected.path) }
        let declared = Set(claim.paths), external = files.map(\.path).filter { !declared.contains($0) }
        let matches = claim.expectedFiles.allSatisfy { expected in after[expected.path]?.digest == expected.digest }
        let kind = !overlapIDs.isEmpty ? "overlapping" : !external.isEmpty ? "external" : !matches ? "unknown" : claim.expectedFiles.isEmpty ? "claimed" : "claimMatched"
        return AttributionAssessment(kind: kind,basis: ["Compared declared paths and exact post-state digests", "No exclusive filesystem authorship is attested"],overlappingChangeIDs: overlapIDs,unclaimedPaths: external)
    }
}
