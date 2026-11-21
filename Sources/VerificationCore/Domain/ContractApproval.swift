public struct ContractApproval: Codable, Sendable, Equatable {
    public let configurationDigest: String
    public let entries: [InputEntry]
    public init(configurationDigest: String,entries: [InputEntry]) { self.configurationDigest = configurationDigest; self.entries = entries.sorted { $0.path < $1.path } }
}
