import Foundation

public struct ExecutionRecord: Codable, Sendable, Equatable {
    public let id: String
    public let descriptorID: String?
    public let inputKey: String
    public let planID: String
    public let jobID: String
    public let state: String
    public let revision: Int
    public let evidenceID: String?
    public let failure: InvarError?
    public init(id: String, descriptorID: String? = nil, inputKey: String, planID: String, jobID: String, state: String, revision: Int, evidenceID: String?, failure: InvarError?) {
        self.id = id
        self.descriptorID = descriptorID
        self.inputKey = inputKey
        self.planID = planID
        self.jobID = jobID
        self.state = state
        self.revision = revision
        self.evidenceID = evidenceID
        self.failure = failure
    }
}
