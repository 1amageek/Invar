public protocol WatchControlling: Sendable {
    func registerWatch(configurationPath: String,budget: RunBudget,key: String,timeout: Double) async throws -> OperationReceipt
    func stopWatch(_ id: String,key: String,timeout: Double) async throws -> OperationReceipt
    func watch(_ id: String) async throws -> WatchRecord
    func watches() async throws -> [WatchRecord]
}
