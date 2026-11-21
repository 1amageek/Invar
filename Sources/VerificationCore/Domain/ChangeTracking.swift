public protocol ChangeTracking: Sendable {
    func beginChange(claim: ChangeClaim?,configurationPath: String?,key: String,timeout: Double) async throws -> OperationReceipt
    func sealChange(_ id: String,key: String,timeout: Double) async throws -> OperationReceipt
    func change(_ id: String) async throws -> ChangeRecord
    func changeRevision(_ id: String) async throws -> ChangeRevision
}
