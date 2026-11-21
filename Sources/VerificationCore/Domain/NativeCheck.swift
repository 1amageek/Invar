import Foundation

public struct NativeCheck: Codable, Sendable, Equatable {
    public let id: String
    public let profile: NativeProfile
    public let expectedTestCount: Int
    public let expectedSignal: Int32?
    public let approved: Bool
    public let required: Bool
    public init(id: String, profile: NativeProfile, expectedTestCount: Int = 1, expectedSignal: Int32? = nil, approved: Bool = false, required: Bool = true) {
        self.id = id; self.profile = profile; self.expectedTestCount = expectedTestCount; self.expectedSignal = expectedSignal; self.approved = approved; self.required = required
    }
}
