import Foundation
import VerificationCore

struct SeededSignedInputs {
    private var state: UInt64
    private let lower: UInt64
    private let distance: UInt64
    init(_ check: FuzzCheck) throws {
        guard let state = UInt64(check.seed), let minimum = Int64(check.minimum), let maximum = Int64(check.maximum), minimum <= maximum else { throw InvarError("INVALID_CONFIGURATION", "Invalid signed fuzz domain", exitCode: 2) }
        self.state = state; lower = UInt64(bitPattern: minimum) ^ (1 << 63)
        distance = (UInt64(bitPattern: maximum) ^ (1 << 63)) - lower
    }
    mutating func next() -> String {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let offset = distance == UInt64.max ? state : state % (distance + 1)
        return String(Int64(bitPattern: (lower &+ offset) ^ (1 << 63)))
    }
}
