import Foundation

public struct ProviderActionState: Codable, Sendable, Equatable {
    public let id: String
    public let revision: Int
    public let jobID: String?
    public let reportedRevision: Int
    public let state: String
    public let failure: InvarError?
    public init(id: String,revision: Int = 1,jobID: String? = nil,reportedRevision: Int = 0,state: String = "preflight",failure: InvarError? = nil) {
        self.id = id; self.revision = revision; self.jobID = jobID; self.reportedRevision = reportedRevision; self.state = state; self.failure = failure
    }
    public func revising(state: String,jobID: String? = nil,reportedRevision: Int? = nil,failure: InvarError? = nil) -> Self {
        Self(id: id,revision: revision+1,jobID: jobID ?? self.jobID,reportedRevision: reportedRevision ?? self.reportedRevision,state: state,failure: failure)
    }
}
