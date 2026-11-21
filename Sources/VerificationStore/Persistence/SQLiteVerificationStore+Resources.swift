import Foundation
import VerificationCore

extension SQLiteVerificationStore {
    public func reserve(_ reservation: StorageReservation) async throws {
        try ensureAccepting()
        try safeID(reservation.id); _ = try Canonical.relative(reservation.relativeRoot)
        guard reservation.maximumBytes > 0, reservation.maximumFiles > 0, reservation.maximumFiles <= policy.maximumFiles else { throw InvarError("RESOURCE_LIMIT","Invalid storage reservation",exitCode: 6) }
        for _ in 0...policy.maximumReservations {
            try Task.checkCancellation()
            let revision = resourceRevision, reservations = try activeReservations()
            if let current = reservations.first(where: { $0.id == reservation.id }) {
                guard current == reservation else { throw InvarError("IMMUTABLE_CONFLICT","Reservation ID changed") }; return
            }
            var ownedPaths: [String] = []
            for existing in reservations { ownedPaths += try ownershipPaths(existing) }
            guard reservations.count < policy.maximumReservations, !ownedPaths.contains(where: { $0 == reservation.relativeRoot || $0.hasPrefix(reservation.relativeRoot + "/") || reservation.relativeRoot.hasPrefix($0 + "/") }) else { throw InvarError("RESOURCE_LIMIT","Reservation capacity or ownership overlap",exitCode: 6) }
            let snapshot = try await diskSnapshot()
            guard revision == resourceRevision else { continue }
            let current = try measuredUsage(snapshot,reservations: reservations)
            var available = policy.maximumRetainedBytes
            for charge in [policy.failureReserveBytes,current.observedBytes,current.reservedBytes,current.databaseReservedBytes] {
                guard charge >= 0, charge <= available else { throw InvarError("STORE_QUOTA","Pinned/retained data and active reservations fill Store quota",exitCode: 6) }
                available -= charge
            }
            guard reservation.maximumBytes <= available else { throw InvarError("STORE_QUOTA","Pinned/retained data and active reservations fill Store quota",exitCode: 6) }
            var reservedFiles = 0
            for existing in reservations {
                let paths = try ownershipPaths(existing)
                let count = snapshot.entries.filter { entry in paths.contains(where: { entry.path == $0 || entry.path.hasPrefix($0 + "/") }) }.count
                reservedFiles += max(0,existing.maximumFiles - count)
            }
            guard reservation.maximumFiles <= policy.maximumFiles - snapshot.files - reservedFiles else { throw InvarError("STORE_QUOTA","File-count reservations fill Store quota",exitCode: 6) }
            try transaction {
                let bytes = try Canonical.encode(reservation)
                try database.insert("reservation",id: reservation.id,bytes: bytes)
                try database.advance("reservation",id: reservation.id,expectedRevision: 0,recordID: reservation.id,state: "active")
            }
            resourceRevision += 1; return
        }
        throw InvarError("RESOURCE_CONTENTION","Concurrent storage changes exhausted bounded admission retries",exitCode: 6)
    }
    public func storageReservations() throws -> [StorageReservation] {
        try ensureAccepting(); return try activeReservations()
    }
    public func abandonedReservationRoot(_ id: String) throws -> URL? {
        try ensureAccepting(); try safeID(id)
        guard let reservation = try activeReservations().first(where: { $0.id == id }) else { return nil }
        guard ["runs/" + id,"preparing/" + id].contains(reservation.relativeRoot) else { throw InvarError("RECOVERY_BLOCKED","Unknown scratch reservation ownership") }
        let path = root.appendingPathComponent(reservation.relativeRoot)
        guard path.resolvingSymlinksInPath().path == path.standardizedFileURL.path else { throw InvarError("RECOVERY_BLOCKED","Abandoned scratch path contains a symlink") }
        return path
    }
    public func discardAbandonedReservation(_ id: String) throws {
        try ensureAccepting(); try safeID(id)
        guard inputWrites == 0, diskReads.isEmpty else { throw InvarError("RECOVERY_BLOCKED","Store has concurrent input/resource operations") }
        guard let reservation = try activeReservations().first(where: { $0.id == id }) else { return }
        guard ["runs/" + id,"preparing/" + id].contains(reservation.relativeRoot) else { throw InvarError("RECOVERY_BLOCKED","Unknown scratch reservation ownership") }
        if let head = try database.head("execution",id: id) {
            guard !["queued","running","cancelling"].contains(head.state) else { throw InvarError("RECOVERY_BLOCKED","Execution physical cleanup must finish before scratch retirement") }
        }
        guard try abandonedReservationRoot(id) != nil else { return }
        let deletion = RetiredStoreObject(kind: "reservation",id: id,relativePath: reservation.relativeRoot)
        try deletion.validate()
        try transaction(usingFailureReserve: true) {
            let bytes = try Canonical.encode(deletion)
            try database.insert("deletion",id: deletion.journalID,bytes: bytes)
            try releaseOwnedReservation(id)
        }
        try recoverRetiredObjects()
    }
    public func releaseReservation(_ id: String) throws {
        try ensureAccepting()
        try releaseOwnedReservation(id)
    }
    func releaseOwnedReservation(_ id: String) throws {
        try database.ensureOpen(); try safeID(id)
        try transaction(usingFailureReserve: true) {
            for transfer in try transfers(id) { try database.retire(.init(kind: "reservationTransfer",id: transfer.id)) }
            try database.removeOwnerLinks(.init(kind: "reservation",id: id))
            try database.removeHead("reservation",id: id); try database.removeRecord("reservation",id: id)
        }
        resourceRevision += 1
    }
    public func usage() async throws -> StoreUsage {
        try ensureAccepting()
        let reservations = try activeReservations()
        let snapshot = try await diskSnapshot()
        return try measuredUsage(snapshot,reservations: reservations)
    }
    public func pin(_ value: RetentionPin) throws {
        try ensureAccepting()
        try safeID(value.id); try safeID(value.ownerID); try safeID(value.objectID)
        guard value.expiresAt.map({ $0.isFinite }) ?? true else { throw InvarError("INVALID_POLICY","Invalid pin expiry") }
        if let current = try database.head("pin",id: value.id), let bytes = try database.load("pin",id: current.recordID) {
            let recorded = try JSONDecoder().decode(RetentionPin.self,from: bytes)
            guard recorded.ownerID == value.ownerID, recorded.ownerKind == value.ownerKind, recorded.objectID == value.objectID, recorded.objectKind == value.objectKind else { throw InvarError("IMMUTABLE_CONFLICT","Pin ownership changed") }
        }
        try transaction {
            guard try database.load(value.objectKind,id: value.objectID) != nil || database.head(value.objectKind,id: value.objectID) != nil else { throw InvarError("RECORD_NOT_FOUND","Retention pin target is not retained") }
            let bytes = try Canonical.encode(value), id = try Canonical.identity(value)
            let current = try database.head("pin",id: value.id)
            try database.insert("pin",id: id,bytes: bytes)
            try database.advance("pin",id: value.id,expectedRevision: current?.revision ?? 0,recordID: id,state: "active")
        }
        resourceRevision += 1
    }
    public func releasePin(_ id: String) throws { try ensureAccepting(); try safeID(id); try database.removeHead("pin",id: id); resourceRevision += 1 }
    func activeReservations() throws -> [StorageReservation] {
        let bytes = try database.current("reservation",states: ["active"],limit: policy.maximumReservations,maximumBytes: 1_048_576)
        return try bytes.map { try JSONDecoder().decode(StorageReservation.self,from: $0) }
    }
    func diskSnapshot() async throws -> StoreDiskInventory.Snapshot {
        let root = self.root, maximumFiles = policy.maximumFiles
        for _ in 0...policy.maximumReservations {
            try ensureAccepting()
            let id = UUID()
            let task = Task.detached { try StoreDiskInventory.scan(root: root,maximumFiles: maximumFiles) }
            diskReads[id] = task
            do {
                let value = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                diskReads.removeValue(forKey: id)
                try ensureAccepting(); return value
            } catch let error as InvarError where error.code == "STORE_SCAN_CHANGED" {
                diskReads.removeValue(forKey: id)
                try Task.checkCancellation()
            } catch { diskReads.removeValue(forKey: id); throw error }
        }
        throw InvarError("RESOURCE_CONTENTION","Published paths changed throughout bounded capacity scan retries",exitCode: 6)
    }
    func measuredUsage(_ snapshot: StoreDiskInventory.Snapshot,reservations: [StorageReservation]) throws -> StoreUsage {
        var reserved = 0
        for reservation in reservations {
            let paths = try ownershipPaths(reservation)
            let owned = snapshot.entries.filter { entry in paths.contains(where: { entry.path == $0 || entry.path.hasPrefix($0 + "/") }) }
            let observed = owned.reduce(0) { $0 + $1.bytes }
            guard observed <= reservation.maximumBytes, owned.count <= reservation.maximumFiles else { throw InvarError("RESOURCE_LIMIT","Owned scratch exceeds its reserved bytes/files",exitCode: 6) }
            let remaining = reservation.maximumBytes - observed
            guard remaining <= Int.max - reserved else { throw InvarError("RESOURCE_LIMIT","Reservation accounting overflow",exitCode: 6) }; reserved += remaining
        }
        guard snapshot.bytes <= policy.maximumRetainedBytes, snapshot.databaseBytes <= 3 * policy.maximumDatabaseBytes else { throw InvarError("STORE_QUOTA","Observed database/WAL/artifact/scratch bytes exceed Store policy",exitCode: 6) }
        return StoreUsage(observedBytes: snapshot.bytes,observedFiles: snapshot.files,reservedBytes: reserved,databaseReservedBytes: 3 * policy.maximumDatabaseBytes - snapshot.databaseBytes,databaseBytes: snapshot.databaseBytes,reservationCount: reservations.count)
    }
}
