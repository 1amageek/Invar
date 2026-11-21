import Foundation

public struct ChangeRecord: Codable, Sendable, Equatable {
    public let id: String
    public let workspaceID: String
    public let ownerPrincipal: String
    public let sessionID: String?
    public let baseline: VerificationInput
    public let claim: ChangeClaim?
    public let state: String
    public let revision: Int
    public let sealedRevisionID: String?
    public init(id: String, workspaceID: String, ownerPrincipal: String, sessionID: String?, baseline: VerificationInput, claim: ChangeClaim?, state: String, revision: Int, sealedRevisionID: String?) {
        self.id = id
        self.workspaceID = workspaceID
        self.ownerPrincipal = ownerPrincipal
        self.sessionID = sessionID
        self.baseline = baseline
        self.claim = claim
        self.state = state
        self.revision = revision
        self.sealedRevisionID = sealedRevisionID
    }
}
