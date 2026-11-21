import Foundation
import VerificationCore

extension SQLiteVerificationStore {
    func transfers(_ reservationID: String) throws -> [ReservationTransfer] {
        let targets = try database.targets(.init(kind: "reservation",id: reservationID),limit: policy.maximumRecords)
        var result: [ReservationTransfer] = []
        for target in targets where target.kind == "reservationTransfer" {
            guard let bytes = try database.load(target.kind,id: target.id) else { throw InvarError("STORE_INTEGRITY","Active reservation transfer is missing") }
            let value = try JSONDecoder().decode(ReservationTransfer.self,from: bytes)
            guard value.id == target.id, value.reservationID == reservationID else { throw InvarError("STORE_INTEGRITY","Reservation transfer identity differs") }
            result.append(value)
        }
        return result
    }
    func ownershipPaths(_ reservation: StorageReservation) throws -> [String] {
        let records = try transfers(reservation.id)
        return [reservation.relativeRoot] + records.map(\.relativeRoot)
    }
    func transferOwnership(from output: URL,relativeRoot: String,objectKind: String,objectID: String) throws {
        let reservations = try activeReservations()
        let path = output.standardizedFileURL.path
        guard let reservation = reservations.first(where: { root.appendingPathComponent($0.relativeRoot).standardizedFileURL.path == path || path.hasPrefix(root.appendingPathComponent($0.relativeRoot).standardizedFileURL.path + "/") }) else { return }
        try transferOwnership(reservation: reservation,relativeRoot: relativeRoot,objectKind: objectKind,objectID: objectID)
    }
    func transferOwnership(reservation: StorageReservation,relativeRoot: String,objectKind: String,objectID: String) throws {
        _ = try Canonical.relative(relativeRoot); try safeID(objectID)
        guard ["artifact":"artifacts","input":"inputs","preparation":"prepared"][objectKind].map({ $0 + "/" + objectID }) == relativeRoot,
            try database.load(objectKind,id: objectID) != nil else { throw InvarError("STORE_INTEGRITY","Transfer lacks its published object") }
        let value = ReservationTransfer(reservationID: reservation.id,relativeRoot: relativeRoot,objectKind: objectKind,objectID: objectID)
        for other in try activeReservations() {
            for path in try ownershipPaths(other) where path == relativeRoot || path.hasPrefix(relativeRoot + "/") || relativeRoot.hasPrefix(path + "/") {
                if other.id == reservation.id, path == relativeRoot { return }
                throw InvarError("RESOURCE_LIMIT","Published transfer overlaps another capacity owner",exitCode: 6)
            }
        }
        try transaction {
            let bytes = try Canonical.encode(value)
            try database.insert("reservationTransfer",id: value.id,bytes: bytes)
            try database.link(ownerKind: "reservation",ownerID: reservation.id,targetKind: "reservationTransfer",targetID: value.id)
            try database.link(ownerKind: "reservationTransfer",ownerID: value.id,targetKind: objectKind,targetID: objectID)
        }
        resourceRevision += 1
    }
}
