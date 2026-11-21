import ArchitectureExtensions
import VerificationCore
import VerificationExplorer

public struct ExplorerServicesBuilder: DaemonServicesBuilding {
    private let manifest: ExtensionManifest
    public init(manifest: ExtensionManifest) { self.manifest = manifest }
    public func make(configuration: DaemonConfiguration,repository: any VerificationRepository,epoch: String,engineIdentity: String,resources: any WorkspaceResourceAdmitting) async throws -> any DaemonWorkspaceServices {
        let connection = try ExplorerProviderConnection(workspace: configuration.workspace.path,stateDirectory: configuration.paths.stateDirectory,manifest: manifest)
        let operations = WorkspaceOperations(source: connection,repository: repository,resources: resources,workspace: configuration.workspace,workspaceID: configuration.paths.workspaceID,epoch: epoch,engineIdentity: engineIdentity,defaultConfigurationPath: configuration.defaultConfigurationPath,scratchFiles: configuration.schedulingPolicy.maximumScratchFiles)
        let publisher = ExplorerPublisher(repository: repository,manifest: manifest,resources: resources) { try await connection.provider() }
        return ExplorerDaemonServices(connection: connection,operations: operations,publisher: publisher,repository: repository,workspaceID: configuration.paths.workspaceID,epoch: epoch,watchPolicy: configuration.watchPolicy,resources: resources,retentionSeconds: configuration.storePolicy.retentionSeconds)
    }
}
