import VerificationCore

public protocol DaemonServicesBuilding: Sendable {
    func make(configuration: DaemonConfiguration,repository: any VerificationRepository,epoch: String,engineIdentity: String,resources: any WorkspaceResourceAdmitting) async throws -> any DaemonWorkspaceServices
}
