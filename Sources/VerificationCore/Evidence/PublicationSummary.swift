public struct PublicationSummary: Codable, Sendable, Equatable {
    public let id: String
    public let revision: Int
    public let state: String
    public let generation: Int?
    public let view: ViewReference?
    public let payloadDigest: String?
    public let completion: String?
    public let diagnosticCode: String?
    public init(_ value: PublicationRecord) {
        id = value.id; revision = value.revision; state = value.state; generation = value.generation; view = value.view
        payloadDigest = value.payload.map(Canonical.digest); completion = value.completion; diagnosticCode = value.failure?.code
    }
}
