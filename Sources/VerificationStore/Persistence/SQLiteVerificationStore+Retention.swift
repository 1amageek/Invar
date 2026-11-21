import Foundation
import VerificationCore

extension SQLiteVerificationStore {
    public func prune(now: Double,maximumObjects: Int) async throws -> RetentionResult {
        try ensureAccepting()
        guard now.isFinite, maximumObjects > 0, maximumObjects <= policy.maximumRecords else { throw InvarError("RESOURCE_LIMIT","Invalid pruning budget",exitCode: 6) }
        try recoverRetiredObjects()
        let revision = resourceRevision
        let disk = try await diskSnapshot()
        try ensureAccepting()
        guard revision == resourceRevision else { throw InvarError("REVISION_CONFLICT","Resource ownership changed during retention scan") }
        var roots = try database.objectKeys(newerThan: now - policy.retentionSeconds,olderThan: nil,limit: policy.maximumRecords)
        if let head = try database.head("policy",id: "active") { roots.append(.init(kind: "policy",id: head.recordID)) }
        let pins = try database.current("pin",states: ["active"],limit: policy.maximumRecords,maximumBytes: 64 * 1024 * 1024)
        for bytes in pins {
            let pin = try JSONDecoder().decode(RetentionPin.self,from: bytes)
            if pin.expiresAt.map({ $0 > now }) ?? true { roots.append(.init(kind: pin.objectKind,id: pin.objectID)); roots.append(.init(kind: "pin",id: pin.id)) }
        }
        let changes = try database.current("change",states: ["open","conflicted"],limit: policy.maximumRecords,maximumBytes: 64 * 1024 * 1024)
        for bytes in changes { let change = try JSONDecoder().decode(ChangeRecord.self,from: bytes); roots.append(.init(kind: "change",id: change.id)) }
        for demand in try pendingDemands() { roots.append(.init(kind: "demand",id: demand.id)) }
        for watch in try watches(states: ["registering","active","paused","stopping"]) { roots.append(.init(kind: "watch",id: watch.id)) }
        for id in try pendingPublicationIDs() { roots.append(.init(kind: "publication",id: id)) }
        for execution in try pendingExecutions() { roots.append(.init(kind: "execution",id: execution.id)) }
        let views = try database.current("view",states: [],limit: policy.maximumRecords,maximumBytes: 64 * 1024 * 1024)
        for bytes in views { let view = try JSONDecoder().decode(ChangeVerificationView.self,from: bytes); let reference = try view.reference(); roots.append(.init(kind: "view",id: reference.id)) }
        for kind in ["source","currentView"] {
            let records = try database.current(kind,states: [],limit: policy.maximumRecords,maximumBytes: 64 * 1024 * 1024)
            for bytes in records {
                let id: String
                if kind == "source" { id = try JSONDecoder().decode(SourceHead.self,from: bytes).id }
                else {
                    let row = try JSONDecoder().decode(PublishedViewHead.self,from: bytes)
                    id = row.id
                }
                roots.append(.init(kind: kind,id: id))
            }
        }
        let reservations = try activeReservations()
        for reservation in reservations { roots.append(.init(kind: "reservation",id: reservation.id)) }
        var protected = Set<SQLiteConnection.ObjectKey>(), pending = roots, offset = 0
        while offset < pending.count {
            try Task.checkCancellation()
            let key = pending[offset]; offset += 1
            if !protected.insert(key).inserted { continue }
            guard protected.count <= policy.maximumRecords else { throw InvarError("RESOURCE_LIMIT","Retained reference closure exceeds its traversal budget",exitCode: 6) }
            if let head = try database.head(key.kind,id: key.id), head.recordID != key.id { pending.append(.init(kind: key.kind,id: head.recordID)) }
            let targets = try database.targets(key,limit: policy.maximumRecords - protected.count)
            pending += targets
        }
        let candidates = try database.objectKeys(newerThan: nil,olderThan: now - policy.retentionSeconds,limit: policy.maximumRecords)
        let removable = candidates.filter { $0.kind != "metadata" && !protected.contains($0) }.prefix(maximumObjects)
        var physical: [RetiredStoreObject] = []
        try transaction(usingFailureReserve: true) {
            for key in removable {
                try database.retire(key)
                let folder: String?
                switch key.kind { case "input": folder = "inputs"; case "artifact": folder = "artifacts"; case "preparation": folder = "prepared"; case "execution": folder = "runs"; default: folder = nil }
                if let folder {
                    let deletion = RetiredStoreObject(kind: key.kind,id: key.id,relativePath: folder + "/" + key.id)
                    let id = deletion.journalID
                    let bytes = try Canonical.encode(deletion)
                    try database.insert("deletion",id: id,bytes: bytes)
                    physical.append(deletion)
                }
            }
        }
        for entry in disk.entries where entry.directory && entry.modifiedAt < now - policy.retentionSeconds {
            let parts = entry.path.split(separator: "/")
            guard parts.count == 2, ["inputs","artifacts","prepared","runs","preparing"].contains(String(parts[0])), !physical.contains(where: { $0.relativePath == entry.path }), !reservations.contains(where: { entry.path == $0.relativeRoot || entry.path.hasPrefix($0.relativeRoot + "/") || $0.relativeRoot.hasPrefix(entry.path + "/") }) else { continue }
            let kind: String
            switch parts[0] { case "inputs": kind = "input"; case "artifacts": kind = "artifact"; case "prepared": kind = "preparation"; case "runs": kind = "execution"; default: kind = "orphan" }
            let id = String(parts[1]), key = SQLiteConnection.ObjectKey(kind: kind,id: id)
            let record = try database.load(kind,id: id), head = try database.head(kind,id: id)
            if protected.contains(key) || record != nil || head != nil { continue }
            let deletion = RetiredStoreObject(kind: "orphan",id: Canonical.parts("orphan",[entry.path]),relativePath: entry.path)
            let bytes = try Canonical.encode(deletion)
            try database.insert("deletion",id: deletion.journalID,bytes: bytes); physical.append(deletion)
            if physical.count >= maximumObjects { break }
        }
        // Retirement commits before unlink; recovery completes only those journals.
        for deletion in physical { try finishRetirement(deletion) }
        resourceRevision += 1
        let remaining = try await diskSnapshot()
        return RetentionResult(removedObjects: removable.map { $0.kind + ":" + $0.id },retainedBytes: remaining.bytes,fileCount: remaining.files)
    }
    public func recoverRetiredObjects() throws {
        try ensureAccepting()
        for id in try database.recordKeys("deletion",limit: policy.maximumRecords) {
            guard let bytes = try database.load("deletion",id: id) else { throw InvarError("STORE_INTEGRITY","Missing retirement journal") }
            let deletion = try JSONDecoder().decode(RetiredStoreObject.self,from: bytes)
            guard deletion.journalID == id else { throw InvarError("STORE_INTEGRITY","Retirement journal identity differs") }
            try finishRetirement(deletion)
        }
    }
    private func finishRetirement(_ deletion: RetiredStoreObject) throws {
        try deletion.validate()
        let path = root.appendingPathComponent(deletion.relativePath)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path); try synchronizeDirectory(path.deletingLastPathComponent()) }
        try database.removeRecord("deletion",id: deletion.journalID)
    }
}
