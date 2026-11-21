public protocol WatchInputProbing: Sendable {
    func probe(configurationPath: String,planID: String,budget: RunBudget) async throws -> WatchInputProbe
}
