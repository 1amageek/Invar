import Foundation

public struct ChangeRevision: Codable, Sendable, Equatable {
    public let id: String
    public let changeID: String
    public let parentID: String?
    public let before: VerificationInput
    public let after: VerificationInput
    public let delta: ObservedDelta
    public let correspondences: [SubjectCorrespondence]
    public let attribution: AttributionAssessment
    public let impactEntityIDs: [String]
    public let impactComplete: Bool
    public let diagnostics: [String]
    public init(id: String, changeID: String, parentID: String?, before: VerificationInput, after: VerificationInput, delta: ObservedDelta, correspondences: [SubjectCorrespondence], attribution: AttributionAssessment, impactEntityIDs: [String], impactComplete: Bool, diagnostics: [String]) {
        self.id = id
        self.changeID = changeID
        self.parentID = parentID
        self.before = before
        self.after = after
        self.delta = delta
        self.correspondences = correspondences
        self.attribution = attribution
        self.impactEntityIDs = impactEntityIDs
        self.impactComplete = impactComplete
        self.diagnostics = diagnostics
    }
    public static func make(changeID: String,parentID: String?,before: VerificationInput,after: VerificationInput,analysis: ChangeAnalysis,diagnostics: [String] = []) throws -> ChangeRevision {
        let delta = try Canonical.identity(analysis.delta), correspondence = try Canonical.identity(analysis.correspondences), attribution = try Canonical.identity(analysis.attribution)
        let id = Canonical.parts("invar.change-revision/2",[changeID,parentID ?? "",before.id,after.id,delta,correspondence,attribution,String(analysis.impactComplete)] + ["impact",String(analysis.impactEntityIDs.count)] + analysis.impactEntityIDs.sorted() + ["diagnostics",String(diagnostics.count)] + diagnostics)
        return ChangeRevision(id: id,changeID: changeID,parentID: parentID,before: before,after: after,delta: analysis.delta,correspondences: analysis.correspondences,attribution: analysis.attribution,impactEntityIDs: analysis.impactEntityIDs,impactComplete: analysis.impactComplete,diagnostics: diagnostics)
    }
}
