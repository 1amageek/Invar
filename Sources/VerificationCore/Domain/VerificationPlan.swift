import Foundation

public struct VerificationPlan: Codable, Sendable, Equatable {
    public let id: String
    public let body: PlanBody
    public init(id: String, body: PlanBody) {
        self.id = id
        self.body = body
    }
}
