import FormalEvidence

public protocol FormalGraphProjecting: Sendable {
    func project(_ page: FormalGraphPage,descriptor: FormalGraphDescriptor,query: FormalGraphQuery,context: FormalProjectionContext) throws -> FormalGraphProjection
}
