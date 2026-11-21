import Foundation

struct NativeObservation: Codable, Sendable {
    let outcome: String
    let classification: String
    let exitCode: Int32
    let testsRun: Int
    let stdoutDigest: String
    let stderrDigest: String
}
