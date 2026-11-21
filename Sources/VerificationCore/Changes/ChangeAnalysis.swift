import Foundation

public struct ChangeAnalysis: Codable, Sendable, Equatable {
    public let delta: ObservedDelta
    public let correspondences: [SubjectCorrespondence]
    public let attribution: AttributionAssessment
    public let impactEntityIDs: [String]
    public let impactComplete: Bool
    public init(delta: ObservedDelta, correspondences: [SubjectCorrespondence], attribution: AttributionAssessment, impactEntityIDs: [String], impactComplete: Bool) {
        self.delta = delta
        self.correspondences = correspondences
        self.attribution = attribution
        self.impactEntityIDs = impactEntityIDs
        self.impactComplete = impactComplete
    }
}
