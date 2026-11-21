import Foundation

public struct FuzzCheck: Codable, Sendable, Equatable {
    public let id: String
    public let profile: NativeProfile
    public let corpus: String
    public let inputEncoding: String
    public let seed: String
    public let minimum: String
    public let maximum: String
    public let iterations: Int
    public let approved: Bool
    public let required: Bool
    public let acceptNoViolationObservedWithinBudget: Bool
    public init(id: String, profile: NativeProfile, corpus: String, inputEncoding: String = "signed64-decimal", seed: String, minimum: String, maximum: String, iterations: Int, approved: Bool = false, required: Bool = true, acceptNoViolationObservedWithinBudget: Bool = false) {
        self.id = id; self.profile = profile; self.corpus = corpus; self.inputEncoding = inputEncoding; self.seed = seed; self.minimum = minimum; self.maximum = maximum; self.iterations = iterations; self.approved = approved; self.required = required; self.acceptNoViolationObservedWithinBudget = acceptNoViolationObservedWithinBudget
    }
}
