import Foundation

public struct RunDemand: Codable, Sendable, Equatable {
    public let id: String
    public let envelopeID: String
    public let principal: String
    public let origin: String
    public let request: WorkspaceOperation
    public var operation: String { request.name }
    public let planID: String?
    public let changeRevisionID: String?
    public let sourceRevision: Int
    public let state: String
    public let revision: Int
    public let executionIDs: [String]
    public let resultID: String?
    public let view: ViewReference?
    public let failure: InvarError?
    public init(id: String, envelopeID: String, principal: String, origin: String, request: WorkspaceOperation, planID: String?, changeRevisionID: String?, sourceRevision: Int = 0, state: String, revision: Int, executionIDs: [String], resultID: String?, failure: InvarError?, view: ViewReference? = nil) {
        self.id = id
        self.envelopeID = envelopeID
        self.principal = principal
        self.origin = origin
        self.request = request
        self.planID = planID
        self.changeRevisionID = changeRevisionID
        self.sourceRevision = sourceRevision
        self.state = state
        self.revision = revision
        self.executionIDs = executionIDs
        self.resultID = resultID; self.view = view
        self.failure = failure
    }
    public func transitioning(to state: String,resultID: String? = nil,executionIDs: [String]? = nil,failure: InvarError? = nil) -> Self {
        Self(id: id,envelopeID: envelopeID,principal: principal,origin: origin,request: request,planID: planID,changeRevisionID: changeRevisionID,sourceRevision: sourceRevision,state: state,revision: revision + 1,executionIDs: executionIDs ?? self.executionIDs,resultID: resultID,failure: failure,view: self.view)
    }

    public func bindingView(_ reference: ViewReference) -> Self {
        Self(id: id,envelopeID: envelopeID,principal: principal,origin: origin,request: request,planID: planID,changeRevisionID: changeRevisionID,sourceRevision: sourceRevision,state: state,revision: revision,executionIDs: executionIDs,resultID: resultID,failure: failure,view: reference)
    }

}
