import FormalEvidence

public enum FormalReadResult: Codable, Sendable, Equatable {
    case opened(FormalReadLease)
    case catalog(EvidenceCatalog)
    case graph(FormalGraphPage)
    case trace(FormalTracePage)
    case origins(OriginPage)
    case document(DocumentChunk)
    case closed
}
