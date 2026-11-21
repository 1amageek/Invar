import Foundation
import VerificationCore

extension SQLiteVerificationStore {
    public func saveAgentSession(_ session: AgentSession) throws {
        try ensureAccepting()
        try safeID(session.id)
        guard session.expiresAt.isFinite, session.policyRevision > 0, !session.principal.isEmpty else { throw InvarError("INVALID_SESSION","Invalid authenticated session record") }
        let bytes = try Canonical.encode(session)
        try database.insert("session",id: session.id,bytes: bytes)
        if try database.load("principalIdentity",id: session.principal) != nil { try database.link(ownerKind: "session",ownerID: session.id,targetKind: "principalIdentity",targetID: session.principal) }
    }
    public func createChange(_ value: ChangeRecord) throws {
        try ensureAccepting()
        try safeID(value.id)
        guard !value.ownerPrincipal.isEmpty, value.state == "open", value.revision == 1, value.sealedRevisionID == nil, value.baseline.workspaceID == value.workspaceID else { throw InvarError("INVALID_CHANGE","New change requires an exact open baseline") }
        _ = try inventory(value.baseline)
        if let session = value.sessionID { guard try database.load("session",id: session) != nil else { throw InvarError("INVALID_SESSION","Change lacks its recorded authenticated session") } }
        let rowID = Canonical.parts("invar.change-head/2",[value.id,"1"])
        let bytes = try Canonical.encode(value)
        try transaction {
            if let head = try database.head("change",id: value.id) {
                guard head.revision == 1, try database.load("change",id: head.recordID) == bytes else { throw InvarError("IMMUTABLE_CONFLICT","Change ID already has a different baseline or claim") }
                return
            }
            try database.insert("change",id: rowID,bytes: bytes)
            try database.advance("change",id: value.id,expectedRevision: 0,recordID: rowID,state: "open")
            try database.link(ownerKind: "change",ownerID: value.id,targetKind: "input",targetID: value.baseline.id)
            try database.link(ownerKind: "change",ownerID: rowID,targetKind: "input",targetID: value.baseline.id)
        }
    }
    public func openChanges(workspaceID: String) throws -> [ChangeRecord] {
        try ensureAccepting()
        let bytes = try database.current("change",states: ["open"],limit: policy.maximumReservations,maximumBytes: 4 * 1024 * 1024)
        let values = try bytes.map { try JSONDecoder().decode(ChangeRecord.self,from: $0) }
        return values.filter { $0.workspaceID == workspaceID }
    }
    public func loadChange(_ id: String) throws -> ChangeRecord {
        try ensureAccepting()
        try safeID(id)
        guard let head = try database.head("change",id: id), let bytes = try database.load("change",id: head.recordID) else { throw InvarError("CHANGE_NOT_FOUND","Unknown change") }
        let value = try JSONDecoder().decode(ChangeRecord.self,from: bytes)
        guard value.id == id, value.revision == head.revision, value.state == head.state else { throw InvarError("STORE_INTEGRITY","Change head differs from immutable record") }
        return value
    }
    public func sealChange(_ revision: ChangeRevision,expectedRevision: Int) throws -> ChangeRecord {
        try ensureAccepting()
        return try transaction {
            let current = try loadChange(revision.changeID)
            if current.sealedRevisionID == revision.id {
                let recorded = try loadChangeRevision(revision.id)
                guard recorded == revision else { throw InvarError("IMMUTABLE_CONFLICT","Repeated seal changed immutable revision bytes") }
                return current
            }
            guard current.revision == expectedRevision, current.baseline == revision.before, current.sealedRevisionID == revision.parentID, ["open","sealed","conflicted"].contains(current.state) else { throw InvarError("REVISION_CONFLICT","Change baseline/head changed during capture") }
            _ = try inventory(revision.before); _ = try inventory(revision.after)
            let analysis = ChangeAnalysis(delta: revision.delta,correspondences: revision.correspondences,attribution: revision.attribution,impactEntityIDs: revision.impactEntityIDs,impactComplete: revision.impactComplete)
            let expected = try ChangeRevision.make(changeID: revision.changeID,parentID: revision.parentID,before: revision.before,after: revision.after,analysis: analysis,diagnostics: revision.diagnostics)
            guard expected == revision else { throw InvarError("INVALID_CHANGE","Change revision identity differs") }
            let conflicted = revision.attribution.kind == "overlapping" || revision.attribution.kind == "unknown" || (current.claim != nil && revision.attribution.kind == "external")
            let next = ChangeRecord(id: current.id,workspaceID: current.workspaceID,ownerPrincipal: current.ownerPrincipal,sessionID: current.sessionID,baseline: current.baseline,claim: current.claim,state: conflicted ? "conflicted" : "sealed",revision: current.revision + 1,sealedRevisionID: revision.id)
            let revisionBytes = try Canonical.encode(revision), recordBytes = try Canonical.encode(next)
            let rowID = Canonical.parts("invar.change-head/2",[next.id,String(next.revision)])
            try database.insert("changeRevision",id: revision.id,bytes: revisionBytes)
            try database.insert("change",id: rowID,bytes: recordBytes)
            try database.advance("change",id: next.id,expectedRevision: expectedRevision,recordID: rowID,state: next.state)
            try database.removeOwnerLinks(.init(kind: "change",id: next.id))
            try database.link(ownerKind: "change",ownerID: next.id,targetKind: "input",targetID: next.baseline.id)
            try database.link(ownerKind: "change",ownerID: next.id,targetKind: "changeRevision",targetID: revision.id)
            try database.link(ownerKind: "change",ownerID: rowID,targetKind: "changeRevision",targetID: revision.id)
            try database.link(ownerKind: "changeRevision",ownerID: revision.id,targetKind: "input",targetID: revision.before.id)
            try database.link(ownerKind: "changeRevision",ownerID: revision.id,targetKind: "input",targetID: revision.after.id)
            return next
        }
    }
    public func loadChangeRevision(_ id: String) throws -> ChangeRevision {
        try ensureAccepting()
        try safeID(id)
        guard let bytes = try database.load("changeRevision",id: id) else { throw InvarError("CHANGE_NOT_FOUND","Unknown sealed revision") }
        let value = try JSONDecoder().decode(ChangeRevision.self,from: bytes)
        guard value.id == id else { throw InvarError("STORE_INTEGRITY","Change revision key differs") }
        return value
    }
    func transaction<Value>(usingFailureReserve: Bool = false,_ body: () throws -> Value) throws -> Value {
        let nested = database.inTransaction
        let savepoint = "owned_" + UUID().uuidString.replacingOccurrences(of: "-",with: "")
        try database.execute(nested ? "SAVEPOINT " + savepoint : "BEGIN IMMEDIATE")
        do {
            let value = try body()
            if !nested { try database.checkQuota(usingFailureReserve: usingFailureReserve) }
            try database.execute(nested ? "RELEASE " + savepoint : "COMMIT")
            return value
        } catch {
            do {
                try database.execute(nested ? "ROLLBACK TO " + savepoint : "ROLLBACK")
                if nested { try database.execute("RELEASE " + savepoint) }
            } catch let cleanup { throw InvarError("STORE_WRITE_FAILED","Transaction failed (\(error)); rollback failed (\(cleanup))") }
            throw error
        }
    }
}
