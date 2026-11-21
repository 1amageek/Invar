/// Last acknowledged complete Explorer publication, independent of assessment order.
public struct PublishedViewHead: Codable, Sendable, Equatable {
    public let publicationID: String
    public let providerID: String
    public let slot: String
    public let generation: Int
    public let view: ViewReference
    public var id: String { Canonical.parts("invar.published-head/2",[publicationID,providerID,slot,String(generation),view.id]) }
    public init(publicationID: String,providerID: String,slot: String,generation: Int,view: ViewReference) {
        self.publicationID = publicationID; self.providerID = providerID; self.slot = slot; self.generation = generation; self.view = view
    }
}
