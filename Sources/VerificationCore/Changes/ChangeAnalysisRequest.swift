import Foundation

public struct ChangeAnalysisRequest: Codable, Sendable, Equatable {
    public let before: CapturedWorkspace
    public let after: CapturedWorkspace
    public let claim: ChangeClaim?
    public let overlaps: [ChangeOverlap]
    public let oraclePaths: [String]
    public let impactRelations: [String]
    public let budget: ChangeAnalysisBudget
    public init(before: CapturedWorkspace, after: CapturedWorkspace, claim: ChangeClaim?, overlaps: [ChangeOverlap], oraclePaths: [String], impactRelations: [String], budget: ChangeAnalysisBudget) {
        self.before = before
        self.after = after
        self.claim = claim
        self.overlaps = overlaps
        self.oraclePaths = oraclePaths
        self.impactRelations = impactRelations
        self.budget = budget
    }
}
