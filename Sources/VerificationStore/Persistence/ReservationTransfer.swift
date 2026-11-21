import Foundation
import VerificationCore

struct ReservationTransfer: Codable {
    let reservationID: String
    let relativeRoot: String
    let objectKind: String
    let objectID: String
    var id: String { Canonical.parts("invar.reservation-transfer/2",[reservationID,relativeRoot]) }
}
