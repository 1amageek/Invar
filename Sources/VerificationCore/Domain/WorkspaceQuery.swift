public enum WorkspaceQuery: Codable, Sendable, Equatable {
    case status
    case receipt(envelopeID: String)
    case demand(id: String)
    case plan(id: String)
    case run(id: String)
    case runRecord(id: String)
    case evidenceSummary(id: String)
    case replay(runID: String)
    case change(id: String)
    case changeRevision(id: String)
    case providerAction(id: String)
    case publication(demandID: String)
    case watch(id: String)
    case watches
    case sourceHead
    case currentView
    case view(id: String)
    case evidence(id: String)
    case association(id: String)
}
