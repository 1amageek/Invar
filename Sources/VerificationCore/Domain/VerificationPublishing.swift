public protocol VerificationPublishing: Sendable {
    func reserve(demand: RunDemand,plan: SchedulingPlan) async throws
    func prepare(demand: RunDemand,run: VerificationRun,view: ChangeVerificationView) async throws -> PublicationRecord
    func abandon(demandID: String,failure: InvarError) async throws
}
