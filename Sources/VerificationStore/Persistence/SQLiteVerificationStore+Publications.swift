import Foundation
import VerificationCore

extension SQLiteVerificationStore {
    public func loadPublication(_ id: String) throws -> PublicationRecord? {
        try ensureAccepting(); try safeID(id)
        guard let head = try database.head("publication",id: id) else { return nil }
        guard let bytes = try database.load("publication",id: head.recordID) else { throw InvarError("STORE_INTEGRITY","Missing publication revision") }
        let value = try JSONDecoder().decode(PublicationRecord.self,from: bytes)
        guard value.id == id, value.revision == head.revision, value.state == head.state else { throw InvarError("STORE_INTEGRITY","Publication head differs") }
        return value
    }
    public func pendingPublicationIDs() throws -> [String] {
        try ensureAccepting()
        return try database.headIDs("publication",states: ["reserving","reserved","ready"],limit: 32)
    }
    public func savePublication(_ value: PublicationRecord,expectedRevision: Int) throws {
        try ensureAccepting(); try safeID(value.id)
        guard value.revision == expectedRevision+1, value.providerID.utf8.count <= 128, value.bindingDigest.count == 64, (value.slot?.utf8.count ?? 0) <= 128,
            (value.handle?.count ?? 0) <= 16384, (value.payload?.count ?? 0) <= 2 * 1024 * 1024,
            (value.failure?.message.utf8.count ?? 0) <= 2048, try inputReference(value.input.id) == value.input else { throw InvarError("INVALID_PUBLICATION","Publication bounds/input differ") }
        try transaction(usingFailureReserve: ["blocked","superseded"].contains(value.state)) {
            let previous = try loadPublication(value.id)
            guard (previous?.revision ?? 0) == expectedRevision else { throw InvarError("REVISION_CONFLICT","Outbox revision changed") }
            if let previous {
                let transitions: [String:Set<String>] = ["reserving":["reserved","blocked"],"reserved":["ready","blocked"],"ready":["ready","committed","delivered","superseded","blocked"],"blocked":["blocked"]]
                guard transitions[previous.state]?.contains(value.state) == true, previous.providerID == value.providerID, previous.entityID == value.entityID, previous.runRequestID == value.runRequestID, previous.input == value.input, previous.bindingDigest == value.bindingDigest,
                    previous.generation == nil || previous.generation == value.generation,
                    previous.slot == nil || previous.slot == value.slot,
                    previous.payload == nil || previous.payload == value.payload,
                    previous.view == nil || previous.view == value.view,
                    previous.completion == nil || previous.completion == value.completion else { throw InvarError("INVALID_TRANSITION","Original publication identity/content cannot change") }
            } else {
                guard value.state == "reserving", value.slot == nil, value.generation == nil, value.handle == nil, value.view == nil, value.payload == nil else { throw InvarError("INVALID_TRANSITION","Publication must start before begin/result work") }
                let active = try pendingPublicationIDs()
                guard active.count < 32 else { throw InvarError("RESOURCE_LIMIT","Publication outbox is full",exitCode: 6) }
            }
            if value.state == "reserved" || value.state == "ready" || value.state == "committed" || value.state == "delivered" {
                guard let generation = value.generation, generation > 0, let slot = value.slot, !slot.isEmpty, value.handle != nil else { throw InvarError("INVALID_PUBLICATION","Publication lacks original reservation") }
            }
            if value.state == "ready" || value.state == "committed" || value.state == "delivered" {
                guard value.payload != nil, let completion = value.completion, ["complete","partial","failed","cancelled","unknown"].contains(completion), value.view != nil else { throw InvarError("INVALID_PUBLICATION","Delivery lacks complete immutable envelope") }
            }
            guard value.state != "committed" || value.completion == "complete", value.state != "delivered" || value.completion != "complete" else { throw InvarError("INVALID_PUBLICATION","Only confirmed complete delivery may select a public head") }
            if let reference = value.view {
                let view = try loadView(reference.id), actual = try view.reference()
                guard reference == actual, view.workspaceID == value.input.workspaceID, value.state == "blocked" || view.input == value.input else { throw InvarError("INPUT_MISMATCH","Publication view belongs to another input") }
            }
            let rowID = Canonical.parts("invar.publication-revision/2",[value.id,String(value.revision)])
            let bytes = try Canonical.encode(value)
            try database.insert("publication",id: rowID,bytes: bytes)
            try database.advance("publication",id: value.id,expectedRevision: expectedRevision,recordID: rowID,state: value.state)
            try database.link(ownerKind: "publication",ownerID: rowID,targetKind: "input",targetID: value.input.id)
            if let view = value.view { try database.link(ownerKind: "publication",ownerID: rowID,targetKind: "view",targetID: view.id) }
            if value.state == "committed" { try selectPublishedView(value,recordID: rowID) }
        }
    }
    func publishedHead(workspaceID: String,entityID: String? = nil) throws -> PublishedViewHead? {
        try ensureAccepting()
        let key = headKey(workspaceID, entityID)
        guard let head = try database.head("currentView",id: key) else { return nil }
        guard let bytes = try database.load("currentView",id: head.recordID) else { throw InvarError("STORE_INTEGRITY","Published view pointer has no retained record") }
        let value = try JSONDecoder().decode(PublishedViewHead.self,from: bytes)
        guard value.id == head.recordID, value.view.workspaceID == workspaceID,
            let publication = try loadPublication(value.publicationID), publication.state == "committed", publication.completion == "complete",
            publication.view == value.view, publication.providerID == value.providerID, publication.slot == value.slot, publication.generation == value.generation else { throw InvarError("STORE_INTEGRITY","Published pointer differs from its confirmed publication") }
        let view = try loadView(value.view.id), reference = try view.reference()
        guard reference == value.view else { throw InvarError("STORE_INTEGRITY","Published pointer differs from its immutable view") }
        return value
    }
    private func headKey(_ workspaceID: String, _ entityID: String?) -> String {
        if let entityID { return Canonical.parts("invar.node-view-head/1", [workspaceID,entityID]) }
        return Canonical.parts("invar.view-head/2", [workspaceID])
    }
    private func selectPublishedView(_ publication: PublicationRecord,recordID: String) throws {
        guard database.inTransaction, let view = publication.view, let slot = publication.slot, let generation = publication.generation else { throw InvarError("INVALID_PUBLICATION","Published selection lacks its original reservation") }
        if let previous = try publishedHead(workspaceID: view.workspaceID,entityID: publication.entityID) {
            guard previous.providerID == publication.providerID, previous.slot == slot else { throw InvarError("PUBLICATION_SCOPE_CONFLICT","Default publication belongs to another provider slot") }
            if previous.generation > generation { return }
            if previous.generation == generation {
                guard previous.publicationID == publication.id, previous.view == view else { throw InvarError("IDEMPOTENCY_CONFLICT","One publication generation cannot select different views") }
                return
            }
        }
        let value = PublishedViewHead(publicationID: publication.id,providerID: publication.providerID,slot: slot,generation: generation,view: view)
        let bytes = try Canonical.encode(value), key = headKey(view.workspaceID, publication.entityID)
        let previous = try database.head("currentView",id: key)
        try database.insert("currentView",id: value.id,bytes: bytes)
        try database.advance("currentView",id: key,expectedRevision: previous?.revision ?? 0,recordID: value.id)
        try database.link(ownerKind: "currentView",ownerID: value.id,targetKind: "view",targetID: view.id)
        try database.link(ownerKind: "currentView",ownerID: value.id,targetKind: "publication",targetID: recordID)
    }

}
