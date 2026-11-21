import FormalEvidence

public enum FormalReadQuery: Codable, Sendable, Equatable {
    case open(evidenceID: String,reference: EvidenceBundleReference,budget: EvidenceReadBudget)
    case catalog(handle: String)
    case graph(handle: String,query: FormalGraphQuery)
    case trace(handle: String,query: FormalTraceQuery)
    case origins(handle: String,query: OriginQuery)
    case document(handle: String,query: DocumentRangeQuery)
    case close(handle: String)
}
