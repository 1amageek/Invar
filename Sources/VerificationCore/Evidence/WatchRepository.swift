public protocol WatchRepository: Sendable {
    func beginWatchStop(_ id: String,principal: String,target: String) async throws -> WatchRecord
    func finishWatchPause(_ id: String) async throws -> WatchRecord
    func pauseWatch(_ id: String,failure: InvarError) async throws -> WatchRecord
    func authorizeWatch(_ id: String) async throws
    func issueWatchEnvelope(watchID: String,operation: WorkspaceOperation,epoch: String,now: Double) async throws -> RequestEnvelope
    func validateWatchRequest(_ envelope: RequestEnvelope,operation: WorkspaceOperation,now: Double) async throws
    func createWatch(_ value: WatchRecord) async throws
    func loadWatch(_ id: String) async throws -> WatchRecord
    func saveWatch(_ value: WatchRecord,expectedRevision: Int) async throws
    func watches(states: [String]) async throws -> [WatchRecord]
}
