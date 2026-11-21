import ArchitectureExtensions
import VerificationCore

public struct FormalGraphProjection: Sendable {
    public let id: String
    public let view: ViewReference
    public let graphID: String
    public let bundleID: String
    public let contribution: ExtensionContribution
    public init(id: String,view: ViewReference,graphID: String,bundleID: String,contribution: ExtensionContribution) {
        self.id = id; self.view = view; self.graphID = graphID; self.bundleID = bundleID; self.contribution = contribution
    }
}
