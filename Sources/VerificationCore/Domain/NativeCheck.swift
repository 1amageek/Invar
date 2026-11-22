import Foundation

public struct NativeCheck: Codable, Sendable, Equatable {
    public let id: String
    public let profile: NativeProfile
    public let expectedTestCount: Int
    public let expectedSignal: Int32?
    public let required: Bool
    public init(id: String, profile: NativeProfile, expectedTestCount: Int = 1, expectedSignal: Int32? = nil, required: Bool = true) {
        self.id = id; self.profile = profile; self.expectedTestCount = expectedTestCount; self.expectedSignal = expectedSignal; self.required = required
    }
}
