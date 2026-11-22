import Foundation

public protocol VerificationScheduling: Sendable {
    func run(_ planID: String, replay: Bool,persist: Bool,demandID: String?) async throws -> VerificationRun
    func shutdown() async
}
