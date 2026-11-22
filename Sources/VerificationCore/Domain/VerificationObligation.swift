public protocol VerificationObligation: Sendable {
    var id: String { get }
    var backend: String { get }
    var required: Bool { get }
    var acceptsUnvalidatedModel: Bool { get }
    var acceptsFuzzBudget: Bool { get }
}
