import Foundation

public struct SourceHead: Codable, Sendable, Equatable {
    public let workspaceID: String
    public let input: VerificationInput
    public let daemonEpoch: String
    public let revision: Int
    public let confirmed: Bool
    public let reason: String?
    public var id: String { Canonical.parts("invar.source-head/2",[workspaceID,input.id,daemonEpoch,String(revision),confirmed ? "confirmed" : "uncertain",reason ?? ""]) }
    public init(workspaceID: String,input: VerificationInput,daemonEpoch: String,revision: Int,confirmed: Bool = true,reason: String? = nil) {
        self.workspaceID = workspaceID; self.input = input; self.daemonEpoch = daemonEpoch; self.revision = revision; self.confirmed = confirmed; self.reason = reason
    }
}
