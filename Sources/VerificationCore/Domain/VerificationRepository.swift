import Foundation

public protocol VerificationRepository: ChangeRepository, ExecutionLedger, EvidenceRepository, RetentionManaging, PolicyRepository, PublicationRepository, WatchRepository, ProviderActionRepository {
    func saveInput(_ capture: CapturedWorkspace) async throws -> String
    func inputReference(_ id: String) async throws -> VerificationInput
    func inputLocation(_ input: VerificationInput) async throws -> URL
    func inputRoot(_ id: String) async throws -> URL
    func capture(_ input: VerificationInput) async throws -> CapturedWorkspace
    func adoptPreparation(_ value: PreparedFormalUnit,from output: URL) async throws
    func inventory(_ input: VerificationInput) async throws -> ScopeInventory
    func preparationOutput(_ id: String) async throws -> URL
    func loadPreparation(_ id: String) async throws -> PreparedFormalUnit?
    func savePreparation(_ value: PreparedFormalUnit) async throws
    func savePlan(_ plan: VerificationPlan) async throws
    func loadPlan(_ id: String) async throws -> VerificationPlan
    func schedulingPlan(_ id: String) async throws -> SchedulingPlan
    func jobReference(_ descriptorID: String) async throws -> JobReference
    func loadDescriptor(_ id: String) async throws -> JobDescriptor
    func reusableEvidence(key: String) async throws -> VerificationEvidence?
    func outputRoot(for id: String) async throws -> URL
    func adoptArtifacts(_ evidence: VerificationEvidence,from output: URL,maximumBytes: Int) async throws
    func artifactRoot(_ reference: EvidenceArtifactReference) async throws -> URL
    func saveRun(_ run: VerificationRun) async throws
    func loadRun(_ id: String) async throws -> VerificationRun
    func saveReplay(originalRunID: String, replayRunID: String) async throws
    func loadReplay(_ replayRunID: String) async throws -> ReplayComparison?
    func shutdown() async throws
}
