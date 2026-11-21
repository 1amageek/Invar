import Foundation

public protocol ChangeRepository: Sendable {
    func saveAgentSession(_ session: AgentSession) async throws
    func createChange(_ value: ChangeRecord) async throws
    func openChanges(workspaceID: String) async throws -> [ChangeRecord]
    func loadChange(_ id: String) async throws -> ChangeRecord
    func sealChange(_ revision: ChangeRevision,expectedRevision: Int) async throws -> ChangeRecord
    func loadChangeRevision(_ id: String) async throws -> ChangeRevision
}
