import Foundation

public protocol ExecutionLedger: Sendable {
    func activateEpoch(_ epoch: String,engineIdentity: String) async throws
    func loadEnvelope(_ id: String) async throws -> RequestEnvelope
    func issueEnvelope(_ envelope: RequestEnvelope,now: Double) async throws -> RequestEnvelope
    func acceptDemand(_ envelope: RequestEnvelope,demand: RunDemand,now: Double) async throws -> OperationReceipt
    func acceptExternalDemand(_ receipt: OperationReceipt,demand: RunDemand,actionID: String) async throws
    func completeDemand(_ demand: RunDemand,run: VerificationRun?,view: ChangeVerificationView?,publication: PublicationRecord?,expectedRevision: Int) async throws
    func completeExecution(_ execution: ExecutionRecord,evidence: VerificationEvidence,expectedRevision: Int) async throws
    func beginDemandCancellation(_ id: String,principal: String,administrative: Bool) async throws -> RunDemand
    func finishDemandFailure(_ id: String,failure: InvarError,cancelled: Bool) async throws -> RunDemand
    func loadDemand(_ id: String) async throws -> RunDemand
    func transitionDemand(_ value: RunDemand,expectedRevision: Int) async throws
    func loadReceipt(_ id: String) async throws -> OperationReceipt?
    func pendingDemands() async throws -> [RunDemand]
    func attachExecution(_ executionID: String,to demandID: String,jobID: String) async throws
    func pendingExecutions() async throws -> [ExecutionRecord]
    func saveExecution(_ value: ExecutionRecord,expectedRevision: Int) async throws
    func loadExecution(_ id: String) async throws -> ExecutionRecord
}

public extension ExecutionLedger {
    func completeDemand(_ demand: RunDemand,run: VerificationRun?,view: ChangeVerificationView?,expectedRevision: Int) async throws {
        try await completeDemand(demand,run: run,view: view,publication: nil,expectedRevision: expectedRevision)
    }
}
