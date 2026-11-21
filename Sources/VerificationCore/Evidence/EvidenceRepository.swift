import Foundation

public protocol EvidenceRepository: Sendable {
    func saveEvidence(_ value: VerificationEvidence) async throws
    func loadEvidence(_ id: String) async throws -> VerificationEvidence
    func saveAssociation(_ value: EvidenceAssociation) async throws
    func loadAssociation(_ id: String) async throws -> EvidenceAssociation
    func observeInput(_ input: VerificationInput,epoch: String) async throws -> SourceHead
    func invalidateSource(workspaceID: String,epoch: String,reason: String) async throws -> SourceHead?
    func sourceHead(workspaceID: String) async throws -> SourceHead?
    func nextViewSequence(workspaceID: String) async throws -> Int
    func commitView(_ value: ChangeVerificationView) async throws -> ViewReference
    func loadView(_ id: String) async throws -> ChangeVerificationView
    func latestView(workspaceID: String) async throws -> ViewReference?
}
