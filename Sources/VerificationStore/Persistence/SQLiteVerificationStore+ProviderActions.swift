import Foundation
import VerificationCore

extension SQLiteVerificationStore {
    public func createProviderAction(_ value: ProviderActionRegistration) throws {
        try ensureAccepting(); try safeID(value.id); try safeID(value.runRequestID)
        guard value.intent.count <= 16384, value.authority.count <= 8192, value.run.count <= 16384,
            value.expiresAt.isFinite, value.expiresAt > Date().timeIntervalSince1970,
            value.envelope.workspaceID == value.input.workspaceID, value.sourceFingerprint.utf8.count == 64,
            value.envelope.fingerprint == (try Canonical.identity(value.operation)), value.envelope.operation == value.operation.name,
            value.envelope.watchID == nil, value.envelope.sessionID != nil else { throw InvarError("INVALID_REQUEST","Provider preflight exceeds fixed identity/size/lifetime bounds") }
        switch value.operation {
        case .verify(let id,let change,let replay,let node):
            if let node { guard node.snapshotID == value.input.snapshotID, try inventory(value.input).entities.contains(where: { $0.id == node.entityID }) else { throw InvarError("INPUT_MISMATCH","External node differs from sealed input") } }
            guard replay == nil, try schedulingPlan(id).input == value.input else { throw InvarError("INPUT_MISMATCH","Provider plan differs from fixed input") }
            if let change { guard try loadChangeRevision(change).after == value.input else { throw InvarError("INPUT_MISMATCH","Provider change differs from fixed input") } }
        case .cancel(let target):
            let demand = try loadDemand(target)
            guard demand.origin == "provider", demand.principal == value.envelope.principal else { throw InvarError("POLICY_DENIED","Provider cancellation exceeds original principal",exitCode: 8) }
        default: throw InvarError("INVALID_REQUEST","Unsupported Provider operation")
        }
        try transaction {
            let rows = try database.current("providerAction",states: ["preflight","accepted","mapped"],limit: 32,maximumBytes: 32 * 8192)
            guard rows.count < 32, try providerAction(value.id) == nil, try providerActionIDs().count < 512 else { throw InvarError("RESOURCE_LIMIT","Provider preflight is duplicated or retained history is full",exitCode: 6) }
            guard try loadEnvelope(value.envelope.id) == value.envelope else { throw InvarError("REQUEST_MISMATCH","Provider preflight envelope changed") }
            let bytes = try Canonical.encode(value)
            try database.insert("providerActionBase",id: value.id,bytes: bytes)
            try database.link(ownerKind: "providerActionBase",ownerID: value.id,targetKind: "envelope",targetID: value.envelope.id)
            try database.link(ownerKind: "providerActionBase",ownerID: value.id,targetKind: "input",targetID: value.input.id)
            if case .verify(let plan,_,_,_) = value.operation { try database.link(ownerKind: "providerActionBase",ownerID: value.id,targetKind: "plan",targetID: plan) }
            try insertProviderActionState(ProviderActionState(id: value.id),expectedRevision: 0)
            try pin(RetentionPin(id: Canonical.parts("provider-action-pin",[value.id]),ownerKind: "providerAction",ownerID: value.id,objectKind: "providerAction",objectID: value.id,expiresAt: value.expiresAt))
        }
    }
    public func providerAction(_ id: String) throws -> ProviderActionRegistration? {
        try ensureAccepting(); try safeID(id)
        guard let bytes = try database.load("providerActionBase",id: id) else { return nil }
        let value = try JSONDecoder().decode(ProviderActionRegistration.self,from: bytes)
        guard value.id == id else { throw InvarError("STORE_INTEGRITY","Provider preflight identity differs") }
        return value
    }
    public func providerActionState(_ id: String) throws -> ProviderActionState {
        try ensureAccepting(); try safeID(id)
        guard let head = try database.head("providerAction",id: id), let bytes = try database.load("providerAction",id: head.recordID) else { throw InvarError("ACTION_NOT_FOUND","Provider mapping is unavailable") }
        let value = try JSONDecoder().decode(ProviderActionState.self,from: bytes)
        guard value.id == id, value.revision == head.revision, value.state == head.state else { throw InvarError("STORE_INTEGRITY","Provider mapping head differs") }
        return value
    }
    public func providerActionIDs() throws -> [String] {
        try ensureAccepting()
        let rows = try database.current("providerAction",states: [],limit: 512,maximumBytes: 512 * 8192)
        return try rows.map { try JSONDecoder().decode(ProviderActionState.self,from: $0).id }
    }
    public func providerActionForDemand(_ id: String) throws -> ProviderActionRegistration? {
        try ensureAccepting(); try safeID(id)
        guard let bytes = try database.load("providerActionDemand",id: id) else { return nil }
        let mapping = try JSONDecoder().decode([String:String].self,from: bytes)
        guard let action = mapping["actionID"], let base = try providerAction(action), try providerActionState(action).jobID == id else { throw InvarError("STORE_INTEGRITY","Provider demand lost its original mapping") }
        return base
    }
    public func saveProviderActionState(_ value: ProviderActionState,expectedRevision: Int) throws {
        try ensureAccepting()
        try transaction(usingFailureReserve: ["outcomeUnknown","rejected","terminal"].contains(value.state)) {
            let old = try providerActionState(value.id)
            let allowed: [String]
            switch old.state {
            case "preflight": allowed = ["accepted","outcomeUnknown","rejected"]
            case "accepted": allowed = ["accepted","mapped","outcomeUnknown"]
            case "mapped": allowed = ["mapped","terminal"]
            case "outcomeUnknown": allowed = ["outcomeUnknown"]
            default: allowed = []
            }
            guard old.revision == expectedRevision, value.revision == expectedRevision+1, allowed.contains(value.state),
                old.jobID == nil || old.jobID == value.jobID, value.reportedRevision >= old.reportedRevision,
                value.state != "mapped" || old.state == "mapped", value.failure.map({ $0.message.utf8.count <= 4096 && $0.code.utf8.count <= 128 }) ?? true else { throw InvarError("INVALID_TRANSITION","Provider mapping cannot widen or reenter execution") }
            if let id = value.jobID { try safeID(id) }
            try insertProviderActionState(value,expectedRevision: expectedRevision)
        }
    }
    func insertProviderActionState(_ value: ProviderActionState,expectedRevision: Int) throws {
        let row = Canonical.parts("invar.provider-action-revision/2",[value.id,String(value.revision)])
        let bytes = try Canonical.encode(value)
        try database.insert("providerAction",id: row,bytes: bytes)
        try database.advance("providerAction",id: value.id,expectedRevision: expectedRevision,recordID: row,state: value.state)
        try database.link(ownerKind: "providerAction",ownerID: row,targetKind: "providerActionBase",targetID: value.id)
        if let id = value.jobID, try database.head("demand",id: id) != nil {
            try database.link(ownerKind: "providerAction",ownerID: row,targetKind: "demand",targetID: id)
        }
    }
}
